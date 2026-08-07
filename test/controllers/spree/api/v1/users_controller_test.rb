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
      display_name: "nova_test",
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
    assert_equal "nova_test", data["display_name"]
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
    get "/api/v1/users/by_handle/nova_test/profile.json"
    assert_response :success
    data = JSON.parse(response.body)["response_data"]
    assert_equal @creator.id, data["id"]
    assert_equal "nova_test", data["display_name"]
  end

  test "GET /api/v1/users/by_handle/:handle/profile is case-insensitive" do
    get "/api/v1/users/by_handle/Nova_Test/profile.json"
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

  test "POST /api/v1/users/sign_up keeps the city and returns it" do
    email = "city#{SecureRandom.hex(4)}@example.com"
    post "/api/v1/users/sign_up.json", params: { user: { email: email, password: "password123", password_confirmation: "password123", city: "Brooklyn" } }
    assert_response :success
    data = JSON.parse(response.body)["response_data"]
    assert_equal "Brooklyn", data["city"]
    assert_equal "Brooklyn", Spree::User.find_by(email: email).city
  ensure
    Spree::User.find_by(email: email)&.destroy
  end

  test "POST /api/v1/users/sign_up without a city returns an empty one" do
    email = "nocity#{SecureRandom.hex(4)}@example.com"
    post "/api/v1/users/sign_up.json", params: { user: { email: email, password: "password123", password_confirmation: "password123" } }
    assert_response :success
    assert_equal "", JSON.parse(response.body)["response_data"]["city"]
  ensure
    Spree::User.find_by(email: email)&.destroy
  end

  test "POST /api/v1/users/sign_in returns the city" do
    @non_creator.update!(city: "Detroit")
    post "/api/v1/users/sign_in.json", params: { user: { email: @non_creator.email, password: "password123" } }
    assert_response :success
    assert_equal "Detroit", JSON.parse(response.body)["response_data"]["city"]
    @non_creator.reload # sign_in saves a new api key, which bumps lock_version
  end

  test "GET /api/v1/users/:id/profile never shows the city" do
    @creator.update!(city: "Detroit")
    get "/api/v1/users/#{@creator.id}/profile.json"
    assert_response :success
    refute JSON.parse(response.body)["response_data"].key?("city")
  end
end
