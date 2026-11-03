require "test_helper"

# The web edits creator fields through the v2 storefront PATCH /account; those now land in
# spree_user_profiles, and the old by_handle endpoint and the new one agree.
class Spree::Api::V2::Storefront::AccountProfileDelegationTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user)
  end

  test "PATCH /api/v2/storefront/account updates the profile" do
    patch "/api/v2/storefront/account", headers: auth(@user), params: {
      user: { display_name: "Web_Handle", bio: "from the web", website: "https://web.example", instagram: "@webig" }
    }, as: :json
    assert_response :success

    profile = @user.reload.profile
    assert_equal "web_handle", profile.handle
    assert_equal "from the web", profile.bio
    assert_equal "https://web.example", profile.website
    assert_equal({ "instagram" => "webig" }, profile.links)

    get "/api/v1/users/by_handle/web_handle/profile.json"
    data = JSON.parse(response.body)["response_data"]
    assert_equal "web_handle", data["display_name"]
    assert_equal "from the web", data["bio"]
    assert_equal "", data["email"]

    get "/api/v1/profiles/web_handle"
    assert_response :success
    assert_equal "from the web", JSON.parse(response.body)["bio"]
  end

  test "PATCH /api/v2/storefront/account with a taken handle is 422 on display_name" do
    create(:user_profile, handle: "already")
    patch "/api/v2/storefront/account", headers: auth(@user), params: { user: { display_name: "already" } }, as: :json
    assert_response :unprocessable_entity
    assert_includes response.body, "is taken"
    assert_nil @user.reload.profile
  end
end
