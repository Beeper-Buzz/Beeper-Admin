# Beeper's digital asset kinds sample_pack, effect_preset and visualizer with their manifest
# validators (Beeper::DigitalKinds, app/services/beeper/manifests/*).
#
# Not installed in the test environment, where the generic modules' tests run against their
# defaults; Beeper's tests turn the kinds on themselves (test/support/beeper_marketplace_test_helper.rb).
Rails.application.config.to_prepare do
  Beeper::DigitalKinds.install! if Beeper::DigitalKinds.install?
end
