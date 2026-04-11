require "test_helper"

class Spree::Admin::UsersControllerDecoratorTest < ActiveSupport::TestCase
  test "permitted_user_attributes includes all creator fields" do
    controller = Spree::Admin::UsersController.new
    attrs = controller.send(:permitted_user_attributes)

    expected_creator_attrs = %i[
      is_creator display_name bio avatar_url banner_url
      website instagram tiktok youtube soundcloud bandcamp
    ]

    expected_creator_attrs.each do |attr|
      assert_includes attrs, attr, "#{attr} should be in permitted_user_attributes"
    end
  end

  test "CREATOR_ATTRIBUTES constant has 11 fields" do
    assert_equal 11, Spree::Admin::UsersControllerDecorator::CREATOR_ATTRIBUTES.length
  end

  test "decorator module is prepended into Spree::Admin::UsersController" do
    assert_includes Spree::Admin::UsersController.ancestors,
                    Spree::Admin::UsersControllerDecorator
  end

  test "permitted_user_attributes still includes original Spree fields (not replaced)" do
    controller = Spree::Admin::UsersController.new
    attrs = controller.send(:permitted_user_attributes)
    # Standard Spree user attribute that should still be there
    assert_includes attrs, :email
  end
end
