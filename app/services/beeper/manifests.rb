module Beeper
  # Manifest validators for Beeper's digital asset kinds (spec §1.5). Each kind's validator is
  # `.call(manifest, asset = nil) -> [String]`: an empty array when the manifest is valid, else one
  # message per problem, naming the field ("samples[3].root_note must be 0..127"). With an asset,
  # the files a manifest names must be attached to it; without one that check is skipped.
  #
  # Beeper::DigitalKinds registers them with DigitalAssets.config through .validator_for, which
  # lets a draft keep an empty manifest (a creator saves details before uploading files) but
  # validates every non-empty draft manifest and every asset being published, and leaves saved
  # published or retired assets alone unless their manifest, kind or files change (.skip?).
  module Manifests
    VALIDATORS = {
      'sample_pack' => 'Beeper::Manifests::SamplePack',
      'effect_preset' => 'Beeper::Manifests::EffectPreset',
      'visualizer' => 'Beeper::Manifests::Visualizer'
    }.freeze

    module_function

    # The DigitalAssets.config.manifest_validators entry for a kind.
    def validator_for(kind)
      validator = VALIDATORS.fetch(kind.to_s)
      lambda do |manifest, asset|
        if skip?(manifest, asset)
          []
        else
          validator.constantize.call(manifest, asset)
        end
      end
    end

    # No validation for
    # - a draft with an empty manifest (a creator saves details before uploading files);
    # - a saved published or retired asset whose manifest, files and kind are unchanged and which
    #   is not being published now (retire!, a touch, a no-op save). Those were checked when they
    #   were published, so retiring a visualizer reads no shader from storage, and a later
    #   narrowing of config/beeper_effects.yml doesn't block retiring an old preset.
    def skip?(manifest, asset)
      return false unless asset

      if asset.draft?
        manifest.is_a?(Hash) && manifest.except('files', :files).empty?
      else
        asset.persisted? && !asset.status_changed?(to: 'published') && !asset.manifest_changed? &&
          !asset.kind_changed? && !asset.attachment_changes.key?('files')
      end
    end

    # The manifest with string keys throughout, or nil when it is not an object. The server-owned
    # "files" key (checksums) is dropped.
    def normalize(manifest)
      return nil unless manifest.is_a?(Hash)

      manifest.deep_stringify_keys.except('files')
    end

    # { filename => blob } of the asset's files, pending attachments included.
    def attached(asset)
      return nil unless asset

      asset.files.attachments.uniq(&:blob_id).each_with_object({}) do |attachment, out|
        out[attachment.blob.filename.to_s] = attachment.blob if attachment.blob
      end
    end

    def integer?(value)
      value.is_a?(Integer)
    end

    def number?(value)
      (value.is_a?(Integer) || value.is_a?(Float)) && value.to_f.finite?
    end

    def boolean?(value)
      [true, false].include?(value)
    end

    def blank_string?(value)
      !value.is_a?(String) || value.strip.empty?
    end
  end
end
