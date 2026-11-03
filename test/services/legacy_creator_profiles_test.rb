require "test_helper"

# Data migration: spree_users creator columns -> spree_user_profiles.
class LegacyCreatorProfilesTest < ActiveSupport::TestCase
  def legacy_user(columns)
    user = create(:user)
    user.update_columns(columns)
    user
  end

  def profile_of(user)
    Spree::UserProfile.find_by(user_id: user.id)
  end

  test "copies display_name, bio, website and socials" do
    user = legacy_user(display_name: "nova", bio: "beats", website: "https://nova.example",
                       instagram: "nova_ig", bandcamp: "novaband", is_creator: true)

    LegacyCreatorProfiles.copy!

    profile = profile_of(user)
    assert_equal "nova", profile.handle
    assert_equal "beats", profile.bio
    assert_equal "https://nova.example", profile.website
    assert_equal({ "instagram" => "nova_ig", "bandcamp" => "novaband" }, profile.links)
    assert_nil profile.name
    assert_nil profile.handle_changed_at, "the copied handle doesn't start the cooldown"
  end

  test "users with only a bio or only socials get a profile without a handle" do
    bio_only = legacy_user(bio: "just a bio")
    social_only = legacy_user(youtube: "chan")
    nothing = create(:user)

    LegacyCreatorProfiles.copy!

    assert_nil profile_of(bio_only).handle
    assert_equal "just a bio", profile_of(bio_only).bio
    assert_equal({ "youtube" => "chan" }, profile_of(social_only).links)
    assert_nil profile_of(nothing)
  end

  test "invalid legacy values are logged and skipped, not fixed" do
    io = StringIO.new
    user = legacy_user(display_name: "admin", bio: "b" * 300, website: "nope")
    other = legacy_user(display_name: "ok_handle", website: "http://fine.example")

    LegacyCreatorProfiles.copy!(logger: Logger.new(io))

    profile = profile_of(user)
    assert_nil profile.handle
    assert_nil profile.bio
    assert_nil profile.website
    log = io.string
    assert_includes log, "user_id=#{user.id}"
    assert_includes log, "handle"
    assert_includes log, "bio"
    assert_includes log, "website"
    assert_equal "ok_handle", profile_of(other).handle
  end

  test "skips users who already have a profile and soft-deleted users" do
    user = legacy_user(display_name: "has_one")
    existing = create(:user_profile, user: user, handle: "kept_handle")
    gone = legacy_user(display_name: "gone_user", deleted_at: Time.current)

    LegacyCreatorProfiles.copy!

    assert_equal "kept_handle", existing.reload.handle
    assert_nil Spree::UserProfile.find_by(user_id: gone.id)
  end

  test "is idempotent" do
    legacy_user(display_name: "twice")
    LegacyCreatorProfiles.copy!
    LegacyCreatorProfiles.copy!
    assert_equal 1, Spree::UserProfile.where(handle: "twice").count
  end

  test "remove! deletes copied rows that were not changed since" do
    untouched = legacy_user(display_name: "untouched")
    edited = legacy_user(display_name: "edited")
    LegacyCreatorProfiles.copy!
    profile_of(edited).update_columns(bio: "changed later", updated_at: 1.minute.from_now)
    own = create(:user_profile, handle: "made_in_app")

    LegacyCreatorProfiles.remove!

    assert_nil profile_of(untouched)
    assert profile_of(edited), "a profile edited after the copy stays"
    assert Spree::UserProfile.exists?(own.id), "profiles of users without legacy fields stay"
  end
end
