module Beeper
  # Beeper's digital asset kinds (spec §1.5): what creators sell and the app can use.
  #   sample_pack    samples for the Sampler (Beeper::Manifests::SamplePack)
  #   effect_preset  settings for the app's effects rack (Beeper::Manifests::EffectPreset)
  #   visualizer     a fragment shader scene (Beeper::Manifests::Visualizer)
  #
  # config/initializers/beeper_marketplace.rb installs them in every environment but test: the
  # generic digital assets and creators tests use their own kinds, and Beeper's tests turn these on
  # with with_beeper_kinds (test/support/beeper_marketplace_test_helper.rb).
  module DigitalKinds
    KINDS = %w[sample_pack effect_preset visualizer].freeze

    module_function

    def apply(config)
      config.kinds = KINDS.dup
      KINDS.each { |kind| config.manifest_validators[kind] = Beeper::Manifests.validator_for(kind) }
      config
    end

    def install?(env = Rails.env)
      !env.test?
    end

    # Registers the kinds with DigitalAssets.configure, so DigitalAssets.reset_config! keeps them.
    def install!
      DigitalAssets.configure { |config| apply(config) }
    end
  end
end
