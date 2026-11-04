require "test_helper"

# Beeper keeps the legacy creator columns until a later cleanup: deletion clears them and removes
# the profile that now holds the live values.
class AccountDeletionBeeperTest < ActiveSupport::TestCase
  test "clears legacy creator columns and deletes the delegated profile" do
    user = create(:user)
    user.update!(display_name: "leaving_now", bio: "bye", instagram: "leaver")
    user.update_columns(display_name: "legacy_name", bio: "legacy bio", website: "https://old.example",
                        instagram: "old", avatar_url: "https://cdn.example.com/a.png", is_creator: true)
    profile_id = user.profile.id

    AccountDeletion.call(user)

    refute Spree::UserProfile.exists?(profile_id)
    row = Spree::User.with_deleted.where(id: user.id)
                     .pluck(:display_name, :bio, :website, :instagram, :avatar_url, :is_creator).first
    assert_equal [nil, nil, nil, nil, nil, false], row
    assert create(:user_profile, handle: "leaving_now").persisted?, "the handle is free again"
  end
end
