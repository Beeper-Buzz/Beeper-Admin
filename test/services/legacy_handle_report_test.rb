require "test_helper"
require "minitest/mock"

# profiles:legacy_handle_report sizes the handles the new rules would refuse. Read-only; prints
# counts and user ids, never a handle, name or email.
class LegacyHandleReportTest < ActiveSupport::TestCase
  def legacy_user(handle, creator: false, email: nil)
    user = create(:user, **(email ? { email: email } : {}))
    user.update_columns(display_name: handle, is_creator: creator)
    user
  end

  def report
    io = StringIO.new
    LegacyHandleReport.run(io: io)
    io.string
  end

  test "counts refusals by reason with the affected user ids" do
    legacy_user("fine_name")
    bad = legacy_user("a__b", creator: true)
    digits = legacy_user("12345", creator: true)
    reserved = legacy_user("shop")
    prefix = legacy_user("beeper_official")

    out = report

    assert_includes out, "users with a legacy handle: 5"
    assert_includes out, "would copy: 1"
    assert_includes out, "refused: 4 (creators: 2)"
    assert_includes out, "invalid: 2 (creators: 2)"
    assert_includes out, "reserved: 2 (creators: 0)"
    assert_match(/invalid.*\n\s*user ids: #{[bad.id, digits.id].sort.join(', ')}/, out)
    assert_match(/reserved.*\n\s*user ids: #{[reserved.id, prefix.id].sort.join(', ')}/, out)
  end

  test "a duplicate differing only in case counts as taken for the later user" do
    first = legacy_user("same_name")
    second = legacy_user("Same_Name")

    out = report

    assert_includes out, "taken: 1 (creators: 0)"
    assert_match(/taken.*\n\s*user ids: #{second.id}\b/, out)
    refute_match(/taken.*\n\s*user ids: .*\b#{first.id}\b/, out)
  end

  test "a handle another user's profile already holds counts as taken; one's own does not" do
    holder = create(:user)
    create(:user_profile, user: holder, handle: "held_name")
    other = legacy_user("held_name")
    own = legacy_user("kept_name")
    Spree::UserProfile.create!(user: own, handle: "kept_name")

    out = report

    assert_includes out, "taken: 1 (creators: 0)"
    assert_match(/taken.*\n\s*user ids: #{other.id}\b/, out)
  end

  test "prints no handles, emails or names" do
    legacy_user("secret__handle", creator: true, email: "person-secret@example.com")

    out = report

    refute_includes out, "secret__handle"
    refute_includes out, "person-secret"
  end

  test "ignores soft-deleted users and blank handles" do
    gone = legacy_user("gone__user")
    gone.update_columns(deleted_at: Time.current)
    legacy_user("")

    assert_includes report, "users with a legacy handle: 0"
  end

  test "writes nothing, and the database itself would refuse a write inside it" do
    legacy_user("a__b")
    before = [Spree::User.unscoped.maximum(:updated_at), Spree::UserProfile.count]

    report

    assert_equal before, [Spree::User.unscoped.maximum(:updated_at), Spree::UserProfile.count]

    conn = ActiveRecord::Base.connection
    error = assert_raises(ActiveRecord::StatementInvalid) do
      LegacyHandleReport.read_only { conn.execute("UPDATE spree_users SET updated_at = now()") }
    end
    assert_match(/read-only/, error.message)
    conn.execute("SELECT 1")
  end

  test "works before the profile table exists" do
    legacy_user("fine_name")
    Spree::UserProfile.stub(:table_exists?, false) do
      assert_includes report, "would copy: 1"
    end
  end
end
