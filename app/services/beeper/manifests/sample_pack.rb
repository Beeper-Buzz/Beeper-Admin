module Beeper
  module Manifests
    # sample_pack (spec §1.5):
    #   { format: 1, pack_id?: /^[a-z0-9-]{3,40}$/, bpm?: number,
    #     samples: [{ file, name, root_note: 0..127 (60), low_note?/high_note?: 0..127 (both or
    #                 neither), one_shot: bool (true), gain_db: -24..12 (0), start_ms?, end_ms?,
    #                 loop?: { start_ms, end_ms }, tags?: [string], pad?: 1..16 }] }
    # 1 to 64 samples (the app loads the first 16). Pads 1-8 are bank A, 9-16 bank B. Every file
    # is an attached wav, aiff, flac or mp3.
    module SamplePack
      PACK_ID = /\A[a-z0-9-]{3,40}\z/.freeze
      AUDIO_EXTENSIONS = %w[wav wave aif aiff flac mp3].freeze
      MAX_SAMPLES = 64

      module_function

      def call(manifest, asset = nil)
        manifest = Manifests.normalize(manifest)
        return ['must be a JSON object'] unless manifest

        errors = []
        errors << 'format must be 1' unless manifest['format'] == 1
        if manifest.key?('pack_id') && !(manifest['pack_id'].is_a?(String) && manifest['pack_id'].match?(PACK_ID))
          errors << 'pack_id invalid (3 to 40 characters of a-z, 0-9 and -)'
        end
        if manifest.key?('bpm') && !(Manifests.number?(manifest['bpm']) && manifest['bpm'].positive? && manifest['bpm'] <= 999)
          errors << 'bpm must be a number above 0 and at most 999'
        end

        samples = manifest['samples']
        unless samples.is_a?(Array) && samples.size.between?(1, MAX_SAMPLES)
          errors << "samples must be a list of 1 to #{MAX_SAMPLES} samples"
          return errors
        end

        files = Manifests.attached(asset)
        pads = {}
        samples.each_with_index do |sample, i|
          errors.concat(sample_errors(sample, "samples[#{i}]", files, pads, i))
        end
        errors
      end

      def sample_errors(sample, at, files, pads, index)
        return ["#{at} must be an object"] unless sample.is_a?(Hash)

        errors = []
        file = sample['file']
        if Manifests.blank_string?(file)
          errors << "#{at}.file is required"
        else
          extension = File.extname(file).delete_prefix('.').downcase
          errors << "#{at}.file \"#{file}\" must be wav, aiff, flac or mp3" unless AUDIO_EXTENSIONS.include?(extension)
          errors << "#{at}.file \"#{file}\" is not attached" if files && !files.key?(file)
        end
        errors << "#{at}.name is required" if Manifests.blank_string?(sample['name'])

        %w[root_note low_note high_note].each do |key|
          next unless sample.key?(key)

          errors << "#{at}.#{key} must be 0..127" unless Manifests.integer?(sample[key]) && sample[key].between?(0, 127)
        end
        errors.concat(zone_errors(sample, at))

        errors << "#{at}.one_shot must be true or false" if sample.key?('one_shot') && !Manifests.boolean?(sample['one_shot'])
        if sample.key?('gain_db') && !(Manifests.number?(sample['gain_db']) && sample['gain_db'].between?(-24, 12))
          errors << "#{at}.gain_db must be -24..12"
        end
        errors.concat(range_errors(sample, at))
        errors.concat(loop_errors(sample['loop'], at)) if sample.key?('loop')
        if sample.key?('tags') && !(sample['tags'].is_a?(Array) && sample['tags'].all? { |t| t.is_a?(String) })
          errors << "#{at}.tags must be a list of strings"
        end
        errors.concat(pad_errors(sample, at, pads, index)) if sample.key?('pad')
        errors
      end

      # low_note and high_note define the key zone: both or neither, low at most high.
      def zone_errors(sample, at)
        low = sample.key?('low_note')
        high = sample.key?('high_note')
        return ["#{at}.low_note given without high_note"] if low && !high
        return ["#{at}.high_note given without low_note"] if high && !low
        return [] unless low && high
        return [] unless Manifests.integer?(sample['low_note']) && Manifests.integer?(sample['high_note'])

        sample['low_note'] > sample['high_note'] ? ["#{at}.low_note must not be above high_note"] : []
      end

      def range_errors(sample, at)
        errors = []
        %w[start_ms end_ms].each do |key|
          next unless sample.key?(key)

          errors << "#{at}.#{key} must be a number of at least 0" unless Manifests.number?(sample[key]) && sample[key] >= 0
        end
        if errors.empty? && sample.key?('start_ms') && sample.key?('end_ms') && sample['end_ms'] <= sample['start_ms']
          errors << "#{at}.end_ms must be after start_ms"
        end
        errors
      end

      def loop_errors(loop, at)
        unless loop.is_a?(Hash) && Manifests.number?(loop['start_ms']) && Manifests.number?(loop['end_ms']) &&
               loop['start_ms'] >= 0
          return ["#{at}.loop needs start_ms and end_ms (numbers of at least 0)"]
        end

        loop['end_ms'] > loop['start_ms'] ? [] : ["#{at}.loop end_ms must be after its start_ms"]
      end

      def pad_errors(sample, at, pads, index)
        pad = sample['pad']
        return ["#{at}.pad must be 1..16"] unless Manifests.integer?(pad) && pad.between?(1, 16)
        return ["#{at}.pad #{pad} is already used by samples[#{pads[pad]}]"] if pads.key?(pad)

        pads[pad] = index
        []
      end
    end
  end
end
