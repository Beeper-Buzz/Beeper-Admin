module Beeper
  module Manifests
    # visualizer (spec §1.5, shader contract §3.6):
    #   { format: 1, shader: "<attached .glsl filename>",
    #     params: [{ name: /^[a-z][a-zA-Z0-9]{0,23}$/, label, min, max, default,
    #                drive?: bass|mid|high|level|beat }] (at most 8) }
    #
    # The .glsl file holds helper functions and `vec4 beeperMain(vec2 uv)` only. The app's prelude
    # declares precision, the uniforms (uTime, uResolution, uBass... and uP_<name> per param) and
    # main, so the file may declare none of them. The server checks the size (64 KB), that
    # beeperMain is defined, and that no forbidden declaration or directive appears outside
    # comments. Compiling happens in the app (with a fallback) and in the web preview.
    #
    # The source checks are a port of the web's checkShaderSource (Beeper-Frontend
    # lib/manifests/visualizer.ts) so creator portal and server never disagree: same comment
    # stripping, same patterns, same messages. Word boundaries are spelled as ASCII lookarounds
    # to match JavaScript's \b. Change both together.
    module Visualizer
      MAX_SHADER_BYTES = 64 * 1024
      MAX_PARAMS = 8
      PARAM_NAME = /\A[a-z][a-zA-Z0-9]{0,23}\z/.freeze
      DRIVES = %w[bass mid high level beat].freeze
      B = '(?<![A-Za-z0-9_])'.freeze # JS \b before a word character
      E = '(?![A-Za-z0-9_])'.freeze # JS \b after a word character
      # JS \s (ECMAScript WhiteSpace and LineTerminator), wider than Ruby's ASCII \s.
      S = "[\\t\\n\\v\\f\\r \\u00a0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000\\ufeff]".freeze
      BEEPER_MAIN = /#{B}vec4#{S}+beeperMain#{S}*\(#{S}*vec2#{S}+[A-Za-z0-9_]+#{S}*\)/.freeze
      # One pass: whichever comment opens first wins ("// a /*" is a line comment, "/* // */" a
      # block comment); an unterminated block comment runs to the end of the file.
      COMMENTS = %r{/\*.*?(?:\*/|\z)|//[^\n]*}m.freeze
      FORBIDDEN = [
        [/##{S}*version#{E}/, '#version not allowed'],
        [/##{S}*extension#{E}/, '#extension not allowed'],
        [/##{S}*include#{E}/, '#include not allowed'],
        [/#{B}precision#{S}+(?:lowp|mediump|highp)#{E}/, 'precision declarations not allowed'],
        [/#{B}uniform#{E}/, 'uniform declarations not allowed'],
        [/#{B}attribute#{E}/, 'attribute declarations not allowed'],
        [/#{B}varying#{E}/, 'varying declarations not allowed'],
        [/#{B}void#{S}+main#{S}*\(/, 'void main not allowed (the host provides main)']
      ].freeze
      TOO_LARGE = 'shader too large (max 64 KB)'.freeze

      module_function

      def call(manifest, asset = nil)
        manifest = Manifests.normalize(manifest)
        return ['must be a JSON object'] unless manifest

        errors = []
        errors << 'format must be 1' unless manifest['format'] == 1
        errors.concat(shader_errors(manifest['shader'], Manifests.attached(asset)))
        errors.concat(params_errors(manifest.fetch('params', [])))
        errors
      end

      def shader_errors(name, files)
        unless name.is_a?(String) && File.extname(name).casecmp?('.glsl')
          return ['shader must name a .glsl file']
        end
        return [] unless files
        return ["shader \"#{name}\" is not attached"] unless files.key?(name)

        blob = files[name]
        # Not downloaded when too large; the web reports the same error for such a file.
        return [TOO_LARGE] if blob.byte_size.to_i > MAX_SHADER_BYTES

        source = begin
          blob.download
        rescue StandardError
          return ['shader could not be read']
        end
        source_errors(source)
      end

      # The web's checkShaderSource: size in UTF-8 bytes, then the patterns on the source with
      # comments removed. Bytes that are not UTF-8 become U+FFFD, as the browser's text decoding
      # does.
      def source_errors(source)
        text = source.dup.force_encoding(Encoding::UTF_8)
        text = text.scrub("�") unless text.valid_encoding?
        errors = []
        errors << TOO_LARGE if text.bytesize > MAX_SHADER_BYTES
        code = strip_comments(text)
        FORBIDDEN.each { |pattern, message| errors << message if code.match?(pattern) }
        errors << 'shader must define beeperMain' unless code.match?(BEEPER_MAIN)
        errors
      end

      # Line comments become one space; block comments keep their line breaks, every other
      # character becomes a space.
      def strip_comments(text)
        text.gsub(COMMENTS) { |m| m.start_with?('//') ? ' ' : m.gsub(/[^\n]/, ' ') }
      end

      def params_errors(params)
        return ["params must be a list of at most #{MAX_PARAMS}"] unless params.is_a?(Array) && params.size <= MAX_PARAMS

        seen = {}
        params.each_with_index.flat_map do |param, i|
          param_errors(param, "params[#{i}]", seen, i)
        end
      end

      def param_errors(param, at, seen, index)
        return ["#{at} must be an object"] unless param.is_a?(Hash)

        errors = []
        name = param['name']
        if !(name.is_a?(String) && name.match?(PARAM_NAME))
          errors << "#{at}.name invalid (a lowercase letter, then up to 23 letters or digits)"
        elsif seen.key?(name)
          errors << "#{at}.name \"#{name}\" repeated (also params[#{seen[name]}])"
        else
          seen[name] = index
        end
        errors << "#{at}.label is required" if Manifests.blank_string?(param['label'])

        numbers = %w[min max default].select { |key| Manifests.number?(param[key]) }
        (%w[min max default] - numbers).each { |key| errors << "#{at}.#{key} must be a number" }
        if numbers.size == 3
          if param['min'] >= param['max']
            errors << "#{at} needs min < max"
          elsif !param['default'].between?(param['min'], param['max'])
            errors << "#{at}.default must be within min..max"
          end
        end
        if param.key?('drive') && !DRIVES.include?(param['drive'])
          errors << "#{at}.drive must be one of #{DRIVES.join(', ')}"
        end
        errors
      end
    end
  end
end
