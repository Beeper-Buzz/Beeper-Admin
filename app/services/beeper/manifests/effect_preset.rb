module Beeper
  module Manifests
    # effect_preset (spec §1.5): { format: 1, effects: [{ id, enabled: bool, params: { name: number } }] }.
    # Ids and parameter ranges are the app's (Beeper::Effects, config/beeper_effects.yml). Each
    # effect appears at most once; params may be partial (the app keeps its defaults for the rest).
    module EffectPreset
      module_function

      def call(manifest, _asset = nil)
        manifest = Manifests.normalize(manifest)
        return ['must be a JSON object'] unless manifest

        errors = []
        errors << 'format must be 1' unless manifest['format'] == 1
        effects = manifest['effects']
        max = Beeper::Effects.ids.size
        unless effects.is_a?(Array) && effects.size.between?(1, max)
          errors << "effects must be a list of 1 to #{max} effects"
          return errors
        end

        seen = {}
        effects.each_with_index do |effect, i|
          errors.concat(effect_errors(effect, "effects[#{i}]", seen, i))
        end
        errors
      end

      def effect_errors(effect, at, seen, index)
        return ["#{at} must be an object"] unless effect.is_a?(Hash)

        id = effect['id']
        definition = Beeper::Effects.params(id) if id.is_a?(String)
        return ["#{at}.id #{id.to_json} unknown (one of #{Beeper::Effects.ids.join(', ')})"] unless definition
        return ["#{at}.id \"#{id}\" repeated (also effects[#{seen[id]}])"] if seen.key?(id)

        seen[id] = index
        errors = []
        errors << "#{at}.enabled must be true or false" unless Manifests.boolean?(effect['enabled'])
        return errors unless effect.key?('params')

        params = effect['params']
        return errors << "#{at}.params must be an object" unless params.is_a?(Hash)

        params.each do |name, value|
          meta = definition[name]
          unless meta
            errors << "#{at}.params.#{name} unknown for #{id}"
            next
          end
          next if Manifests.number?(value) && value.between?(meta['min'], meta['max'])

          errors << "#{at}.params.#{name} must be a number in #{meta['min']}..#{meta['max']}"
        end
        errors
      end
    end
  end
end
