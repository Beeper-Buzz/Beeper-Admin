require 'test_helper'

# Beeper copy on the generic marketplace screens: the admin product tab, the manifest guide on the
# digital asset form, and the order confirmation email for orders with digital items.
class BeeperMarketplaceCopyTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers

  setup do
    # Spree::Store.default is cached in Rails.cache; an earlier test's rolled-back store would
    # leave the orders below with a store the mailer can't load.
    Rails.cache.clear
    @admin = create(:user)
    @admin.spree_roles << Spree::Role.find_or_create_by!(name: 'admin')
    @product = create(:digital_product, name: 'Drum Pack')
  end

  teardown do
    Warden.test_reset!
  end

  test 'the product tab is "Beeper content"' do
    login_as(@admin, scope: :spree_user)
    get "/admin/products/#{@product.slug}/edit"
    assert_response :success
    assert_includes response.body, 'Beeper content'
  end

  test 'the digital asset form explains the Beeper kinds and their manifests' do
    login_as(@admin, scope: :spree_user)
    get "/admin/products/#{@product.slug}/digital_assets/new"
    assert_response :success
    body = response.body
    assert_includes body, 'Beeper manifests'
    %w[sample_pack effect_preset visualizer beeperMain].each { |text| assert_includes body, text }
    Beeper::Effects.ids.each { |id| assert_includes body, id }
  end

  test 'the confirmation email of an order with a digital item points to the Beeper Library' do
    buyer = create(:user)
    asset = published_asset(price: 5, kind: 'sample_pack')
    order = complete_order!(creator_cart_order(buyer, [asset.variant.product, 1]))

    html = Spree::OrderMailer.confirm_email(order.id).html_part&.body.to_s.presence ||
           Spree::OrderMailer.confirm_email(order.id).body.to_s
    assert_includes html, 'Library'
    assert_includes html, 'beeper.buzz/account/library'
  end

  test 'the confirmation email of a physical-only order says nothing about downloads' do
    order = complete_order!(cart_order(user: create(:user)))

    html = Spree::OrderMailer.confirm_email(order.id).html_part&.body.to_s.presence ||
           Spree::OrderMailer.confirm_email(order.id).body.to_s
    refute_includes html, 'beeper.buzz/account/library'
  end
end
