require "test_helper"

# The web's users/:id/profile and by_handle endpoints read the profile and honour moderation.
class Spree::Api::V1::LegacyProfileModerationTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user)
    @profile = create(:user_profile, user: @user, handle: "webby", bio: "hi")
  end

  def response_code
    JSON.parse(response.body)["response_code"]
  end

  test "hidden profiles are 404 on both legacy endpoints" do
    @profile.update_column(:hidden_at, Time.current)
    get "/api/v1/users/by_handle/webby/profile.json"
    assert_equal 404, response_code
    get "/api/v1/users/#{@user.id}/profile.json"
    assert_equal 404, response_code
  end

  test "locked accounts are 404" do
    @user.update_column(:locked_at, Time.current)
    get "/api/v1/users/by_handle/webby/profile.json"
    assert_equal 404, response_code
  end

  test "a viewer in a block gets 404 by handle" do
    viewer = create(:user)
    Spree::UserBlock.block!(@user, viewer)
    get "/api/v1/users/by_handle/webby/profile.json", headers: auth(viewer)
    assert_equal 404, response_code
  end

  test "avatar_url prefers the uploaded avatar" do
    @user.update_columns(avatar_url: "https://cdn.example.com/old.png")
    old_hosts = ENV["PROFILE_AVATAR_URL_HOSTS"]
    ENV["PROFILE_AVATAR_URL_HOSTS"] = "cdn.example.com"
    Profiles.reset_config!
    get "/api/v1/users/by_handle/webby/profile.json"
    assert_equal "https://cdn.example.com/old.png", JSON.parse(response.body)["response_data"]["avatar_url"]

    @profile.avatar.attach(fixture_upload("avatar.png", "image/png"))
    get "/api/v1/users/by_handle/webby/profile.json"
    url = JSON.parse(response.body)["response_data"]["avatar_url"]
    assert_includes url, "/rails/active_storage/representations/"
  ensure
    ENV["PROFILE_AVATAR_URL_HOSTS"] = old_hosts
    Profiles.reset_config!
  end
end
