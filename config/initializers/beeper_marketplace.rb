# Beeper's marketplace settings on top of the generic modules (digital_assets.rb, uploads.rb,
# creators.rb, affiliates.rb):
# - digital asset kinds sample_pack, effect_preset and visualizer with their manifest validators
#   (Beeper::DigitalKinds, app/services/beeper/manifests/*);
# - uploads: .glsl shaders at most 64 KB, json manifests 256 KB (Beeper::Marketplace.apply_uploads);
# - affiliate links on https://beeper.buzz unless AFFILIATE_LINK_BASE_URL is set.
# The creators marketplace taxon is "marketplace" (CREATORS_MARKETPLACE_TAXON), which
# rake beeper:marketplace:seed creates.
#
# Not installed in the test environment, where the generic modules' tests run against their
# defaults; Beeper's tests turn the settings on themselves (test/support/beeper_marketplace_test_helper.rb).
Rails.application.config.to_prepare do
  Beeper::Marketplace.install! if Beeper::DigitalKinds.install?
end
