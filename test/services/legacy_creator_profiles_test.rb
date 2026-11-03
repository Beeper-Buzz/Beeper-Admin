require "test_helper"
require "minitest/mock"

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

  test "the count covers only rows that gained a value" do
    legacy_user(display_name: "gains_one")
    legacy_user(display_name: "admin")
    legacy_user(website: "nope")
    legacy_user(bio: "b" * 300)
    legacy_user(instagram: "i" * 101)
    io = StringIO.new

    assert_equal 1, LegacyCreatorProfiles.copy!(logger: Logger.new(io))

    assert_includes io.string, "copied 1 profiles"
    assert_equal 5, Spree::UserProfile.count, "refused-only users still get their empty row, as before"
  end

  test "skips soft-deleted users" do
    gone = legacy_user(display_name: "gone_user", deleted_at: Time.current)

    LegacyCreatorProfiles.copy!

    assert_nil Spree::UserProfile.find_by(user_id: gone.id)
  end

  test "fills blanks on a profile created before the copy" do
    user = legacy_user(display_name: "windowed", bio: "old bio", instagram: "ig", tiktok: "tk")
    existing = create(:user_profile, user: user, handle: nil, website: "https://w.example", links: { "youtube" => "chan" })

    assert_equal 1, LegacyCreatorProfiles.copy!

    existing.reload
    assert_equal "windowed", existing.handle
    assert_equal "old bio", existing.bio
    assert_equal "https://w.example", existing.website
    assert_equal({ "youtube" => "chan", "instagram" => "ig", "tiktok" => "tk" }, existing.links)
    assert_nil existing.handle_changed_at, "filling a blank handle doesn't start the cooldown"
  end

  test "never overwrites a value the profile already has" do
    user = legacy_user(display_name: "old_handle", bio: "old bio", website: "https://old.example", instagram: "old_ig")
    existing = create(:user_profile, user: user, handle: "new_handle", bio: "new bio", website: "https://new.example",
                                     links: { "instagram" => "new_ig" })
    updated_at = existing.reload.updated_at

    assert_equal 0, LegacyCreatorProfiles.copy!

    existing.reload
    assert_equal "new_handle", existing.handle
    assert_equal "new bio", existing.bio
    assert_equal "https://new.example", existing.website
    assert_equal({ "instagram" => "new_ig" }, existing.links)
    assert_equal updated_at, existing.updated_at, "nothing to fill, row untouched"
  end

  test "a refused legacy value doesn't disturb an existing profile" do
    user = legacy_user(display_name: "admin", bio: "fills in")
    existing = create(:user_profile, user: user, handle: nil, name: "Kept Name")

    LegacyCreatorProfiles.copy!

    existing.reload
    assert_nil existing.handle
    assert_equal "fills in", existing.bio
    assert_equal "Kept Name", existing.name
  end

  test "filling blanks is idempotent" do
    user = legacy_user(display_name: "windowed", bio: "old bio")
    existing = create(:user_profile, user: user, handle: nil)

    assert_equal 1, LegacyCreatorProfiles.copy!
    updated_at = existing.reload.updated_at
    assert_equal 0, LegacyCreatorProfiles.copy!
    assert_equal updated_at, existing.reload.updated_at
  end

  test "one over-long social value drops only that key" do
    io = StringIO.new
    user = legacy_user(instagram: "i" * 101, tiktok: "tk", youtube: "yt", soundcloud: "sc", bandcamp: "bc")

    LegacyCreatorProfiles.copy!(logger: Logger.new(io))

    assert_equal({ "tiktok" => "tk", "youtube" => "yt", "soundcloud" => "sc", "bandcamp" => "bc" }, profile_of(user).links)
    assert_includes io.string, "user_id=#{user.id}"
    assert_includes io.string, "links.instagram"
    refute_includes io.string, "i" * 101
  end

  test "a unique-index race on one user doesn't abort the transaction for the rest" do
    first = legacy_user(display_name: "race_name")
    holder = create(:user_profile, handle: "race_name")
    second = legacy_user(bio: "still copied")
    io = StringIO.new

    Profiles::HandlePolicy.stub(:taken?, false) do
      LegacyCreatorProfiles.copy!(logger: Logger.new(io))
    end

    assert holder.reload.persisted?
    assert_nil profile_of(first)&.handle
    assert_equal "still copied", profile_of(second).bio
    assert_includes io.string, "user_id=#{first.id}"
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
