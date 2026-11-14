# Beeper's marketplace settings (Beeper::DigitalKinds, Beeper::Marketplace) are installed in every
# environment but test, so the generic digital assets, creators and affiliates tests run against
# the modules' defaults. Beeper's own tests turn them on for a block.
module BeeperMarketplaceTestHelper
  def with_beeper_kinds
    Beeper::DigitalKinds.apply(DigitalAssets.config)
    yield
  ensure
    DigitalAssets.reset_config!
  end
end

ActiveSupport::TestCase.include(BeeperMarketplaceTestHelper)
