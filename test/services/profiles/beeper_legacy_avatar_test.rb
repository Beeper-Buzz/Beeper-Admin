require "test_helper"

# spree_users.avatar_url is a URL the user typed. Remove photo has to clear it, reports have to
# record it, and it's only served from hosts named in PROFILE_AVATAR_URL_HOSTS.
class Profiles::BeeperLegacyAvatarTest < ActionDispatch::IntegrationTest
  URL = "https://cdn.example.com/a.png".freeze

  setup do
    @user = create(:user)
    @user.update_columns(avatar_url: URL)
    @profile = create(:user_profile, user: @user, handle: "legacyav")
    @old_hosts = ENV["PROFILE_AVATAR_URL_HOSTS"]
    allow_hosts(nil)
  end

  teardown do
    allow_hosts(@old_hosts)
  end

  def allow_hosts(value)
    ENV["PROFILE_AVATAR_URL_HOSTS"] = value
    Profiles.reset_config!
  end

  def presented
    Profiles::Presenter.new(@profile.reload, base_url: "https://api.example.com").avatar
  end

  test "not served from a host off the allow-list, which is empty by default" do
    assert_nil presented

    get "/api/v1/profiles/legacyav.json"
    assert_nil json["avatar"]
  end

  test "served from an allowed host" do
    allow_hosts("cdn.example.com")
    assert_equal({ small: URL, large: URL }, presented)
  end

  test "the old profile endpoints use the same rule" do
    get "/api/v1/users/by_handle/legacyav/profile.json"
    assert_nil json["response_data"]["avatar_url"]

    allow_hosts("cdn.example.com")
    get "/api/v1/users/#{@user.id}/profile.json"
    assert_equal URL, json["response_data"]["avatar_url"]
  end

  test "the same rule without a profile row" do
    plain = create(:user)
    plain.update_columns(avatar_url: URL)

    get "/api/v1/users/#{plain.id}/profile.json"
    assert_nil json["response_data"]["avatar_url"]
  end

  test "remove_photo clears the legacy URL" do
    allow_hosts("cdn.example.com")
    Profiles::Moderation.remove_photo(@profile)

    assert_nil @user.reload.avatar_url
    assert_nil presented
  end

  test "remove_photo clears both an upload and the legacy URL" do
    @profile.avatar.attach(fixture_upload("avatar.png", "image/png"))
    Profiles::Moderation.remove_photo(@profile)

    assert_nil @user.reload.avatar_url
    refute @profile.reload.avatar.attached?
  end

  test "DELETE avatar clears the legacy URL too" do
    delete "/api/v1/profile/avatar", headers: auth(@user)

    assert_response :success
    assert_nil @user.reload.avatar_url
  end

  test "DELETE avatar clears the legacy URL when the user has no profile row" do
    plain = create(:user)
    plain.update_columns(avatar_url: URL)

    delete "/api/v1/profile/avatar", headers: auth(plain)

    assert_response :success
    assert_nil plain.reload.avatar_url
    assert_nil json["avatar"]
  end

  test "the owner's GET /profile shows their legacy avatar whatever its host, https only" do
    get "/api/v1/profile.json", headers: auth(@user)
    assert_equal({ "small" => URL, "large" => URL }, json["avatar"])

    @user.update_columns(avatar_url: "http://cdn.example.com/a.png")
    get "/api/v1/profile.json", headers: auth(@user)
    assert_nil json["avatar"]
  end

  test "the report snapshot records a legacy avatar" do
    snapshot = Spree::ContentReport.profile_snapshot(@profile)

    assert_equal true, snapshot["avatar"]
    assert_equal URL, snapshot["avatar_url"]
    assert_nil snapshot["avatar_blob_id"]
  end

  test "a snapshot without any photo says so" do
    @user.update_columns(avatar_url: nil)
    snapshot = Spree::ContentReport.profile_snapshot(@profile.reload)

    assert_equal false, snapshot["avatar"]
    assert_nil snapshot["avatar_url"]
  end
end
