require "test_helper"

class Spree::Api::V2::Storefront::AccountControllerDecoratorTest < ActiveSupport::TestCase
  test "STOREFRONT_CREATOR_ATTRIBUTES contains 10 fields (NOT is_creator)" do
    attrs = Spree::Api::V2::Storefront::AccountControllerDecorator::STOREFRONT_CREATOR_ATTRIBUTES
    assert_equal 10, attrs.length
  end

  test "STOREFRONT_CREATOR_ATTRIBUTES excludes is_creator" do
    attrs = Spree::Api::V2::Storefront::AccountControllerDecorator::STOREFRONT_CREATOR_ATTRIBUTES
    assert_not_includes attrs, :is_creator,
                        "is_creator MUST NOT be in the storefront permit list"
  end

  test "STOREFRONT_CREATOR_ATTRIBUTES includes all expected user-editable creator fields" do
    attrs = Spree::Api::V2::Storefront::AccountControllerDecorator::STOREFRONT_CREATOR_ATTRIBUTES
    expected = %i[display_name bio avatar_url banner_url website instagram tiktok youtube soundcloud bandcamp]
    expected.each do |field|
      assert_includes attrs, field, "#{field} should be in STOREFRONT_CREATOR_ATTRIBUTES"
    end
  end

  test "decorator module is prepended into Spree::Api::V2::Storefront::AccountController" do
    assert_includes Spree::Api::V2::Storefront::AccountController.ancestors,
                    Spree::Api::V2::Storefront::AccountControllerDecorator
  end

  test "spree_user_params does NOT permit is_creator even if sent" do
    params_hash = {
      user: {
        email: "test@example.com",
        display_name: "tester",
        is_creator: true, # attempting to set admin-only field
        bio: "A bio"
      }
    }
    params = ActionController::Parameters.new(params_hash)
    permitted = params.require(:user).permit(
      Spree::PermittedAttributes.user_attributes +
        Spree::Api::V2::Storefront::AccountControllerDecorator::STOREFRONT_CREATOR_ATTRIBUTES
    )

    assert_not permitted.key?(:is_creator),
               "is_creator should be stripped by strong params"
    assert permitted.key?(:display_name), "display_name should pass through"
    assert permitted.key?(:bio), "bio should pass through"
    assert permitted.key?(:email), "email should pass through (stock Spree permitted attr)"
  end
end
