require "test_helper"

# Beeper's shipped lists: "beeper" is a reserved handle and a reserved prefix. Admins may take
# those handles through the app's API; members may not; the other rules hold for both.
class Spree::Api::V1::AdminReservedHandlesTest < ActionDispatch::IntegrationTest
  BRAND = %w[beeper beeperbuzz beeperhq beeper123 beeper_buzz].freeze

  setup do
    Profiles.reset_config!
    @admin = make_admin(create(:user))
    @member = create(:user)
  end

  teardown { Profiles.reset_config! }

  def available(handle, user)
    get "/api/v1/profiles/handle_available", params: { handle: handle }, headers: auth(user)
    assert_response :success
    json
  end

  test "handle_available: brand handles are free for an admin and reserved for a member" do
    BRAND.each do |handle|
      assert_equal({ "available" => true, "reason" => nil }, available(handle, @admin), "admin #{handle}")
      assert_equal({ "available" => false, "reason" => "reserved" }, available(handle, @member), "member #{handle}")
    end
  end

  test "handle_available: an admin still gets invalid and taken" do
    create(:user_profile, user: make_admin(create(:user)), handle: "beeper_fan")
    assert_equal({ "available" => false, "reason" => "invalid" }, available("beeper_", @admin))
    assert_equal({ "available" => false, "reason" => "invalid" }, available("beeper__hq", @admin))
    assert_equal({ "available" => false, "reason" => "taken" }, available("Beeper_Fan", @admin))
  end

  test "PATCH profile: an admin takes a brand handle, a member is refused" do
    patch "/api/v1/profile", headers: auth(@member), params: { profile: { handle: "beeperhq" } }, as: :json
    assert_response :unprocessable_entity
    assert_equal ["is reserved"], json["fields"]["handle"]

    patch "/api/v1/profile", headers: auth(@admin), params: { profile: { handle: "BeeperHQ" } }, as: :json
    assert_response :success
    assert_equal "beeperhq", json["handle"]

    assert_equal({ "available" => false, "reason" => "taken" }, available("beeperhq", make_admin(create(:user))))
    assert_equal({ "available" => false, "reason" => "reserved" }, available("beeperhq", @member))
  end
end
