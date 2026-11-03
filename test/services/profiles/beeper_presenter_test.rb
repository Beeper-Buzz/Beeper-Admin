require "test_helper"

class Profiles::BeeperPresenterTest < ActiveSupport::TestCase
  setup do
    @old_hosts = ENV["PROFILE_AVATAR_URL_HOSTS"]
    ENV["PROFILE_AVATAR_URL_HOSTS"] = "cdn.example.com"
    Profiles.reset_config!
  end

  teardown do
    ENV["PROFILE_AVATAR_URL_HOSTS"] = @old_hosts
    Profiles.reset_config!
  end

  test "avatar falls back to spree_users.avatar_url on an allowed host when nothing is attached" do
    user = create(:user)
    user.update_columns(avatar_url: "https://cdn.example.com/a.png")
    profile = create(:user_profile, user: user, handle: "fallback")
    avatar = Profiles::Presenter.new(profile, base_url: "https://api.example.com").public_json[:avatar]
    assert_equal({ small: "https://cdn.example.com/a.png", large: "https://cdn.example.com/a.png" }, avatar)
  end

  test "an attached avatar wins over avatar_url" do
    user = create(:user)
    user.update_columns(avatar_url: "https://cdn.example.com/a.png")
    profile = create(:user_profile, user: user, handle: "attached")
    profile.avatar.attach(fixture_upload("avatar.png", "image/png"))
    avatar = Profiles::Presenter.new(profile, base_url: "https://api.example.com").public_json[:avatar]
    assert avatar[:small].start_with?("https://api.example.com/rails/active_storage/")
  end

  test "no fallback for a non-https avatar_url or none" do
    user = create(:user)
    user.update_columns(avatar_url: "http://cdn.example.com/a.png")
    profile = create(:user_profile, user: user, handle: "plainhttp")
    assert_nil Profiles::Presenter.new(profile).public_json[:avatar]
  end

  test "is_creator comes from spree_users" do
    user = create(:user)
    user.update_columns(is_creator: true)
    profile = create(:user_profile, user: user, handle: "creator_x")
    assert_equal true, Profiles::Presenter.new(profile).public_json[:is_creator]
  end
end
