require "test_helper"

# A private profile shows only handle, name and photo. The old endpoints keep their envelope for
# the web but blank the rest for anyone but the owner.
class Spree::Api::V1::LegacyPrivateProfileTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create(:user)
    @owner.update_columns(is_creator: true, banner_url: "https://cdn.example.com/banner.png")
    @profile = create(:user_profile, user: @owner, handle: "privy", bio: "secret bio", website: "https://p.example",
                                     visibility: "private", links: { "instagram" => "privy_ig" })
    create_public_favorite(@owner, name: "Secret Fav")
    UserFollow.create!(follower: create(:user), following: @owner)
    UserFollow.create!(follower: @owner, following: create(:user))
  end

  def by_handle(headers: {})
    get "/api/v1/users/by_handle/privy/profile.json", headers: headers
    json["response_data"]
  end

  def by_id(headers: {})
    get "/api/v1/users/#{@owner.id}/profile.json", headers: headers
    json["response_data"]
  end

  def assert_blanked(data)
    assert_equal 0, data["followers_count"]
    assert_equal 0, data["following_count"]
    assert_nil data["bio"]
    assert_nil data["website"]
    assert_nil data["banner_url"]
    assert_equal({}, data["socials"])
    assert_equal [], data["public_favorites"]
    assert_equal [], data["recent_streams"]
    assert_equal "privy", data["display_name"], "handle stays"
    assert_includes data.keys, "avatar_url"
    refute_includes response.body, "secret bio"
    refute_includes response.body, "privy_ig"
    refute_includes response.body, "Secret Fav"
  end

  test "anonymous callers get the blanked envelope on both endpoints" do
    assert_blanked by_handle
    assert_blanked by_id
  end

  test "a signed-in non-owner gets the blanked envelope" do
    headers = auth(create(:user))
    assert_blanked by_handle(headers: headers)
    assert_blanked by_id(headers: headers)
  end

  test "the owner still sees everything" do
    headers = auth(@owner)
    [by_handle(headers: headers), by_id(headers: headers)].each do |data|
      assert_equal "secret bio", data["bio"]
      assert_equal "https://p.example", data["website"]
      assert_equal "https://cdn.example.com/banner.png", data["banner_url"]
      assert_equal({ "instagram" => "privy_ig" }, data["socials"])
      assert_equal 1, data["public_favorites"].size
      assert_equal 1, data["followers_count"]
      assert_equal 1, data["following_count"]
    end
  end

  test "a public profile is unchanged" do
    @profile.update_columns(visibility: "public")
    data = by_handle
    assert_equal "secret bio", data["bio"]
    assert_equal({ "instagram" => "privy_ig" }, data["socials"])
    assert_equal 1, data["public_favorites"].size
    assert_equal 1, data["followers_count"]
    assert_equal 1, data["following_count"]
  end
end
