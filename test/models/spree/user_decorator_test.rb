require "test_helper"

class Spree::UserDecoratorTest < ActiveSupport::TestCase
  def build_user(attrs = {})
    Spree::User.new({
      email: "test#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    }.merge(attrs))
  end

  # A creator whose legacy handle the rules refused: is_creator true, no handle on the profile.
  def creator_without_handle(profile: true)
    user = create(:user, password: "password123", password_confirmation: "password123")
    user.update_columns(is_creator: true)
    create(:user_profile, user: user, handle: nil, bio: "still here") if profile
    Spree::User.find(user.id)
  end

  test "an existing creator with no handle can still save, reset a password and get an api key" do
    [creator_without_handle, creator_without_handle(profile: false)].each do |user|
      assert user.valid?, user.errors.full_messages.join(", ")
      assert user.reset_password("newpassword1", "newpassword1"), user.errors.full_messages.join(", ")
      user = Spree::User.find(user.id)
      user.generate_spree_api_key!
      assert user.reload.spree_api_key.present?
    end
  end

  test "the forms' blank display_name counts as unchanged for a creator with no handle" do
    [creator_without_handle, creator_without_handle(profile: false)].each do |user|
      assert user.update(display_name: "", bio: "edited in a form"), user.errors.full_messages.join(", ")
      user = Spree::User.find(user.id)
      assert_nil user.display_name
      assert_equal "edited in a form", user.bio
    end
  end

  test "an existing creator with no handle can pick one through the form" do
    user = creator_without_handle
    assert user.update(display_name: "picked_one"), user.errors.full_messages.join(", ")
    assert_equal "picked_one", Spree::User.find(user.id).display_name
  end

  test "an existing creator with no handle can edit the rest of their profile" do
    user = creator_without_handle
    user.bio = "new bio"
    assert user.save, user.errors.full_messages.join(", ")
    assert_equal "new bio", Spree::User.find(user.id).bio
  end

  test "becoming a creator without a handle is refused" do
    user = create(:user)
    user = Spree::User.find(user.id)
    user.is_creator = true
    refute user.valid?
    assert user.errors[:display_name].present?
  end

  test "a new creator needs a handle" do
    user = build_user(is_creator: true)
    refute user.valid?
    assert user.errors[:display_name].present?
  end

  test "blanking the handle while a creator is refused" do
    user = creator_without_handle
    user.display_name = "has_handle"
    assert user.save, user.errors.full_messages.join(", ")
    user = Spree::User.find(user.id)
    user.display_name = ""
    refute user.valid?
    assert user.errors[:display_name].present?
  end

  test "beeper is reserved as a prefix" do
    Profiles.reset_config!
    %w[beeper beeper_official beeperfan beeper2].each do |handle|
      assert_equal :reserved, Profiles::HandlePolicy.check(handle, user: nil), handle
    end
    assert_equal :ok, Profiles::HandlePolicy.check("mybeeper", user: nil)
  end

  test "an admin may set a beeper handle through display_name; a member may not" do
    Profiles.reset_config!
    admin = make_admin(create(:user))
    admin.update(display_name: "beeperhq")
    assert admin.errors.empty?, admin.errors.full_messages.join(", ")
    assert_equal "beeperhq", admin.reload.profile.handle

    member = create(:user)
    refute member.update(display_name: "beeper123")
    assert_includes member.errors[:display_name], "is reserved"
  end

  test "allows nil display_name" do
    user = build_user(display_name: nil)
    assert user.valid?, user.errors.full_messages.join(", ")
  end

  test "accepts 3-30 chars of a-z0-9_" do
    user = build_user(display_name: "buzzer_99")
    assert user.valid?, user.errors.full_messages.join(", ")
  end

  test "normalizes uppercase display_name to lowercase" do
    user = build_user(display_name: "Buzzer99")
    user.save!
    assert_equal "buzzer99", user.reload.display_name
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
