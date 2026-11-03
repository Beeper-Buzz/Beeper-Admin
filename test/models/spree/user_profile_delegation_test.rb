require "test_helper"

# Until the web moves to the profile endpoints, the creator accessors on spree_users
# (display_name, bio, website, socials) read and write spree_user_profiles.
class Spree::UserProfileDelegationTest < ActiveSupport::TestCase
  def build_user(attrs = {})
    Spree::User.new({ email: "deleg#{SecureRandom.hex(4)}@example.com", password: "password123" }.merge(attrs))
  end

  test "writes go to the profile, not the legacy columns" do
    user = build_user(display_name: "Nova_1", bio: "beats", website: "https://nova.example",
                      instagram: "https://instagram.com/nova", soundcloud: "@nova")
    user.save!

    profile = Spree::UserProfile.find_by!(user_id: user.id)
    assert_equal "nova_1", profile.handle
    assert_equal "beats", profile.bio
    assert_equal "https://nova.example", profile.website
    assert_equal({ "instagram" => "nova", "soundcloud" => "nova" }, profile.links)

    row = Spree::User.where(id: user.id).pluck(:display_name, :bio, :website, :instagram).first
    assert_equal [nil, nil, nil, nil], row, "legacy columns are no longer written"
  end

  test "reads come from the profile" do
    user = create(:user)
    user.update_columns(display_name: "legacy", bio: "old bio")
    create(:user_profile, user: user, handle: "fresh", bio: "new bio", links: { "tiktok" => "fresh" })
    user = Spree::User.find(user.id)
    assert_equal "fresh", user.display_name
    assert_equal "new bio", user.bio
    assert_equal "fresh", user.tiktok
    assert_nil user.youtube
  end

  test "a user without a profile reads nil and reading creates nothing" do
    user = create(:user)
    assert_nil user.display_name
    assert_nil user.bio
    assert_nil user.instagram
    refute Spree::UserProfile.exists?(user_id: user.id)
  end

  test "blank social clears the link" do
    user = create(:user)
    create(:user_profile, user: user, handle: "linker", links: { "instagram" => "x", "tiktok" => "y" })
    user = Spree::User.find(user.id)
    user.update!(instagram: "")
    assert_equal({ "tiktok" => "y" }, user.profile.reload.links)
  end

  test "profile errors surface on the user under the legacy names" do
    create(:user_profile, handle: "taken_one")
    user = build_user(display_name: "taken_one", website: "ftp://nope", bio: "b" * 281)
    refute user.save
    assert_includes user.errors[:display_name], "is taken"
    assert user.errors[:website].any?
    assert user.errors[:bio].any?
    refute Spree::User.exists?(email: user.email)
  end

  test "beeper reserved handles and web routes are refused" do
    %w[beeper beeperbuzz beeper_buzz delta8 team cart checkout signup].each do |handle|
      user = build_user(display_name: handle)
      refute user.valid?, handle
      assert_includes user.errors[:display_name], "is reserved", handle
    end
  end

  test "saving the user without touching profile fields leaves the profile alone" do
    user = create(:user)
    profile = create(:user_profile, user: user, handle: "steady")
    user = Spree::User.find(user.id)
    user.update!(avatar_url: "https://example.com/a.png")
    assert_equal profile.updated_at.to_i, profile.reload.updated_at.to_i
  end
end
