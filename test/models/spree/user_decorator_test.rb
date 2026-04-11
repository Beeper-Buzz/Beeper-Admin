require "test_helper"

class Spree::UserDecoratorTest < ActiveSupport::TestCase
  def build_user(attrs = {})
    Spree::User.new({
      email: "test#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    }.merge(attrs))
  end

  test "allows nil display_name" do
    user = build_user(display_name: nil)
    assert user.valid?, user.errors.full_messages.join(", ")
  end

  test "accepts 3-30 chars of a-z0-9_" do
    user = build_user(display_name: "beeper_99")
    assert user.valid?, user.errors.full_messages.join(", ")
  end

  test "normalizes uppercase display_name to lowercase" do
    user = build_user(display_name: "Beeper99")
    user.save!
    assert_equal "beeper99", user.reload.display_name
  end

  test "rejects special chars in display_name" do
    user = build_user(display_name: "beep.er")
    assert_not user.valid?
  end

  test "rejects reserved slug 'cart' as display_name" do
    user = build_user(display_name: "cart")
    assert_not user.valid?
  end

  test "rejects display_name shorter than 3 chars" do
    user = build_user(display_name: "ab")
    assert_not user.valid?
  end

  test "enforces case-insensitive uniqueness of display_name" do
    build_user(display_name: "aaron").save!
    dup = build_user(display_name: "Aaron")
    assert_not dup.valid?
  end

  test "requires display_name when is_creator is true" do
    user = build_user(is_creator: true, display_name: nil)
    assert_not user.valid?
    assert user.errors[:display_name].present?
  end

  test "allows is_creator false without display_name" do
    user = build_user(is_creator: false, display_name: nil)
    assert user.valid?, user.errors.full_messages.join(", ")
  end

  test "rejects http avatar_url (requires https)" do
    user = build_user(display_name: "tester", avatar_url: "http://example.com/a.jpg")
    assert_not user.valid?
  end

  test "accepts https avatar_url" do
    user = build_user(display_name: "tester", avatar_url: "https://example.com/a.jpg")
    assert user.valid?, user.errors.full_messages.join(", ")
  end

  test "strips protocol and domain from instagram field" do
    user = build_user(display_name: "tester1", instagram: "https://instagram.com/beeper_buzz")
    user.save!
    assert_equal "beeper_buzz", user.reload.instagram
  end

  test "strips leading @ from tiktok field" do
    user = build_user(display_name: "tester2", tiktok: "@some_user")
    user.save!
    assert_equal "some_user", user.reload.tiktok
  end

  test "leaves bare youtube handle unchanged" do
    user = build_user(display_name: "tester3", youtube: "chan_handle")
    user.save!
    assert_equal "chan_handle", user.reload.youtube
  end
end
