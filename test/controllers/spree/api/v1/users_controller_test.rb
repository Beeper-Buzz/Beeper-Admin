require "test_helper"

class Spree::Api::V1::UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @non_creator = Spree::User.create!(
      email: "noncreator#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
    @creator = Spree::User.create!(
      email: "creator#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      is_creator: true,
      display_name: "beeper_test",
      bio: "Making music",
      instagram: "beeper_buzz",
      website: "https://beeper.buzz"
    )
  end

  teardown do
    @non_creator&.destroy
    @creator&.destroy
  end

  test "GET /api/v1/users/:id/profile returns extended shape for non-creator" do
    get "/api/v1/users/#{@non_creator.id}/profile.json"
    assert_response :success
    data = JSON.parse(response.body)["response_data"]
    assert_equal @non_creator.id, data["id"]
    assert_equal false, data["is_creator"]
    assert_nil data["display_name"]
    assert_nil data["bio"]
    assert_nil data["avatar_url"]
    assert_nil data["banner_url"]
    assert_equal({}, data["socials"])
    assert_equal [], data["recent_streams"]
  end

  test "GET /api/v1/users/:id/profile returns creator fields for creator" do
    get "/api/v1/users/#{@creator.id}/profile.json"
    assert_response :success
    data = JSON.parse(response.body)["response_data"]
    assert_equal true, data["is_creator"]
    assert_equal "beeper_test", data["display_name"]
    assert_equal "Making music", data["bio"]
    assert_equal "beeper_buzz", data["socials"]["instagram"]
    assert_equal "https://beeper.buzz", data["website"]
  end

  test "GET /api/v1/users/:id/profile returns 404 for missing user" do
    get "/api/v1/users/999999999/profile.json"
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 404, body["response_code"]
    assert_equal "User not found", body["response_message"]
  end

  test "GET /api/v1/users/by_handle/:handle/profile finds creator by handle" do
    get "/api/v1/users/by_handle/beeper_test/profile.json"
    assert_response :success
    data = JSON.parse(response.body)["response_data"]
    assert_equal @creator.id, data["id"]
    assert_equal "beeper_test", data["display_name"]
  end

  test "GET /api/v1/users/by_handle/:handle/profile is case-insensitive" do
    get "/api/v1/users/by_handle/Beeper_Test/profile.json"
    assert_response :success
    data = JSON.parse(response.body)["response_data"]
    assert_equal @creator.id, data["id"]
  end

  test "GET /api/v1/users/by_handle/:handle/profile returns 404 for unknown handle" do
    get "/api/v1/users/by_handle/nonexistent/profile.json"
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 404, body["response_code"]
    assert_equal "User not found", body["response_message"]
  end
end
