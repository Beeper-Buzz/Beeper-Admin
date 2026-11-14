module Beeper
  module Marketplace
    # Publishes the Starter Kit's files from a directory (rake beeper:marketplace:starter_kit[dir]).
    # The directory is what the app's scripts/make-starter-kit.mjs writes: the WAVs and a
    # manifest.json (a sample_pack manifest with pack_id "starter-kit", spec §3.5), so the copy
    # buyers claim is the same pack the app bundles.
    #
    # Runs the seed first. Attaches the files the manifest names (manifest.json itself is not
    # attached: the library serves the manifest), publishes them as the kit's next version and puts
    # the product on sale. Running it again with the same manifest and files changes nothing;
    # changed files publish a new version (owners get it through the library).
    #
    # Returns { status: :published | :unchanged, product:, asset: }. Raises Invalid, before
    # uploading anything, when the manifest is invalid or names a missing file.
    module StarterKit
      PACK_ID = 'starter-kit'.freeze
      CONTENT_TYPES = { 'wav' => 'audio/wav', 'wave' => 'audio/wav', 'aif' => 'audio/aiff', 'aiff' => 'audio/aiff',
                        'flac' => 'audio/flac', 'mp3' => 'audio/mpeg' }.freeze

      class Invalid < StandardError; end

      module_function

      def call(dir)
        dir = Pathname.new(dir.to_s)
        manifest = read_manifest(dir)
        paths = file_paths(dir, manifest)
        product = Seed.call[:starter_kit]
        live = product.master.live_digital_asset

        if live && same?(live, manifest, paths)
          live.store_checksums! unless checksums_complete?(live)
          put_on_sale(product)
          return { status: :unchanged, product: product, asset: live }
        end

        asset = publish(product, manifest, paths)
        put_on_sale(product)
        { status: :published, product: product.reload, asset: asset }
      end

      def read_manifest(dir)
        path = dir.join('manifest.json')
        raise Invalid, "#{path} not found" unless path.file?

        manifest = JSON.parse(path.read)
        raise Invalid, 'manifest.json must hold a JSON object' unless manifest.is_a?(Hash)

        manifest = manifest.except('files')
        errors = Beeper::Manifests::SamplePack.call(manifest)
        errors << "pack_id must be \"#{PACK_ID}\" (the app matches the bundled kit by it)" unless manifest['pack_id'] == PACK_ID
        raise Invalid, "Starter Kit manifest: #{errors.join('; ')}" if errors.any?

        manifest
      rescue JSON::ParserError => e
        raise Invalid, "manifest.json is not valid JSON: #{e.message}"
      end

      # { filename => path } for every file the manifest names.
      def file_paths(dir, manifest)
        names = manifest['samples'].map { |sample| sample['file'] }.uniq
        missing = names.reject { |name| File.basename(name) == name && dir.join(name).file? }
        raise Invalid, "Starter Kit files missing from #{dir}: #{missing.join(', ')}" if missing.any?

        names.index_with { |name| dir.join(name) }
      end

      def same?(asset, manifest, paths)
        return false unless asset.kind == 'sample_pack' && asset.manifest.except('files') == manifest

        current = asset.file_entries.to_h { |file| [file[:filename], file[:md5]] }
        current == paths.transform_values { |path| Digest::MD5.file(path).base64digest }
      end

      def publish(product, manifest, paths)
        blobs = paths.map do |name, path|
          extension = File.extname(name).delete_prefix('.').downcase
          File.open(path, 'rb') do |io|
            ActiveStorage::Blob.create_and_upload!(io: io, filename: name, identify: false,
                                                   content_type: CONTENT_TYPES.fetch(extension, 'application/octet-stream'))
          end
        end
        asset = Spree::DigitalAsset.new(variant: product.master, kind: 'sample_pack', manifest: manifest)
        asset.files.attach(blobs)
        errors = Beeper::Manifests::SamplePack.call(manifest, asset)
        raise Invalid, "Starter Kit manifest: #{errors.join('; ')}" if errors.any?

        Spree::DigitalAsset.transaction do
          asset.save!
          asset.publish!
        end
        # In-process: the task runs in a one-off dyno, where a job on the async queue would die
        # with the process.
        asset.store_checksums!
        asset
      end

      # Whether manifest["files"] holds a sha256 for every attached file.
      def checksums_complete?(asset)
        asset.file_entries.all? { |file| file[:sha256].present? }
      end

      def put_on_sale(product)
        product.update!(available_on: Time.current) unless product.available_on && product.available_on <= Time.current
      end
    end
  end
end
