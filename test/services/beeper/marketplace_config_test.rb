require 'test_helper'

# Beeper's settings for the generic marketplace modules (config/initializers/beeper_marketplace.rb).
class Beeper::MarketplaceConfigTest < ActiveSupport::TestCase
  test 'uploads: shaders are capped at 64 KB, json stays at 256 KB, audio and images unchanged' do
    config = Beeper::Marketplace.apply_uploads(Uploads::Config.new)

    assert_equal 64.kilobytes, config.rule_for('rings.glsl', 'text/plain')[:max_bytes]
    assert_equal 64.kilobytes, config.rule_for('rings.glsl', 'application/octet-stream')[:max_bytes]
    assert_equal 256.kilobytes, config.rule_for('manifest.json', 'application/json')[:max_bytes]
    assert_nil config.rule_for('notes.txt', 'text/plain')
    assert_equal 50.megabytes, config.rule_for('kick.wav', 'audio/wav')[:max_bytes]
    assert_equal 10.megabytes, config.rule_for('cover.png', 'image/png')[:max_bytes]
  end

  test 'affiliates: links point at beeper.buzz unless AFFILIATE_LINK_BASE_URL says otherwise' do
    config = Affiliates::Config.new
    with_env('AFFILIATE_LINK_BASE_URL' => nil) { Beeper::Marketplace.apply_affiliates(config) }
    assert_equal 'https://beeper.buzz', config.link_base_url

    config = Affiliates::Config.new
    with_env('AFFILIATE_LINK_BASE_URL' => 'https://staging.beeper.buzz/') { Beeper::Marketplace.apply_affiliates(config) }
    assert_equal 'https://staging.beeper.buzz', config.link_base_url
  end

  test 'an affiliate link built with the Beeper settings' do
    Beeper::Marketplace.apply_affiliates(Affiliates.config)
    account = AffiliateAccount.new(code: 'djbeep')
    assert_equal 'https://beeper.buzz/?ref=djbeep', account.link
    assert_equal 'https://beeper.buzz/browse?ref=djbeep', account.link('/browse')
  ensure
    Affiliates.reset_config!
  end

  test 'creators: the marketplace taxon is the seeded "marketplace" permalink' do
    assert_equal 'marketplace', Creators.config.marketplace_taxon_permalink
    assert_equal 'creator', Creators.config.role_name
    assert_equal 'Digital', Creators.config.shipping_category_name
  end

  private

  def with_env(values)
    saved = values.keys.index_with { |key| ENV[key] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| ENV[key] = value }
  end
end
