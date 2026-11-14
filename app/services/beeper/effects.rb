module Beeper
  # The app's effects and parameter ranges (config/beeper_effects.yml, copied from BeeperNative's
  # src/data/effects.ts). effect_preset manifests may only name these effects and parameters.
  module Effects
    DEFINITIONS = YAML.safe_load(File.read(Rails.root.join('config', 'beeper_effects.yml')))
                      .fetch('effects').transform_values { |params| params.transform_values(&:freeze).freeze }.freeze

    module_function

    # The nine effect ids, in the app's order.
    def ids
      DEFINITIONS.keys
    end

    # { param => { 'min', 'max', 'default', 'step' } } for an effect id, or nil.
    def params(id)
      DEFINITIONS[id.to_s]
    end
  end
end
