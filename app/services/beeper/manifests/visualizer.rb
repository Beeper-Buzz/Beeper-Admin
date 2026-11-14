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
    module Visualizer
      MAX_SHADER_BYTES = 64.kilobytes
      MAX_PARAMS = 8
      PARAM_NAME = /\A[a-z][a-zA-Z0-9]{0,23}\z/.freeze
      DRIVES = %w[bass mid high level beat].freeze
      BEEPER_MAIN = /\bvec4\s+beeperMain\s*\(\s*vec2\s+\w+\s*\)\s*\{/.freeze
      FORBIDDEN = [
        [/\bvoid\s+main\s*\(/, 'void main not allowed (the app provides main)'],
        [/^\s*#\s*version\b/, '#version not allowed'],
        [/^\s*#\s*extension\b/, '#extension not allowed'],
        [/^\s*#\s*include\b/, '#include not allowed'],
        [/\buniform\b/, 'uniform declarations not allowed (declare params in the manifest)'],
        [/\battribute\b/, 'attribute declarations not allowed'],
        [/\bvarying\b/, 'varying declarations not allowed'],
        [/\bprecision\b/, 'precision statements not allowed']
      ].freeze

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
        return ["shader too large (at most #{MAX_SHADER_BYTES / 1.kilobyte} KB)"] if blob.byte_size.to_i > MAX_SHADER_BYTES

        source = begin
          blob.download
        rescue StandardError
          return ['shader could not be read']
        end
        source_errors(source)
      end

      # Checks GLSL source text (comments removed first).
      def source_errors(source)
        return ["shader too large (at most #{MAX_SHADER_BYTES / 1.kilobyte} KB)"] if source.bytesize > MAX_SHADER_BYTES

        text = source.dup.force_encoding(Encoding::UTF_8)
        return ['shader must be UTF-8 text'] unless text.valid_encoding?

        code = strip_comments(text)
        errors = FORBIDDEN.filter_map { |pattern, message| "shader: #{message}" if code.match?(pattern) }
        errors.unshift('shader must define beeperMain: vec4 beeperMain(vec2 uv) { ... }') unless code.match?(BEEPER_MAIN)
        errors
      end

      def strip_comments(text)
        text.gsub(%r{/\*.*?\*/}m, ' ').gsub(%r{//[^\n]*}, '')
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
