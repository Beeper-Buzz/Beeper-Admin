# One-off copy of the creator columns on spree_users (display_name, bio, website, socials) into
# spree_user_profiles. Used by the 20261103130000 data migration.
#
# - Only live users with at least one of those columns set.
# - display_name -> handle, socials -> links; name stays empty (display_name was the handle).
# - Only blanks are filled. A profile row created before the copy keeps every value it has and
#   gains the legacy ones it lacks, so running this again is harmless.
# - A value the profile rules refuse (bad or reserved handle, bio over 280, non-http website, one
#   over-long social) is logged with the user id and left out; it is never rewritten.
# - remove! (migration down) deletes copied profiles nobody has changed since.
class LegacyCreatorProfiles
  SOCIALS = %w[instagram tiktok youtube soundcloud bandcamp].freeze
  FIELDS = (%w[display_name bio website] + SOCIALS).freeze

  def self.copy!(logger: Rails.logger)
    new(logger).copy!
  end

  def self.remove!
    new(Rails.logger).remove!
  end

  def initialize(logger)
    @logger = logger
  end

  def copy!
    copied = 0
    legacy_users.find_each do |user|
      copied += 1 if copy_user(user)
    end
    @logger.info("[legacy_creator_profiles] copied #{copied} profiles")
    copied
  end

  def remove!
    profiles = Spree::UserProfile.where(user_id: legacy_users.select(:id)).where('updated_at = created_at')
    with_avatar = ActiveStorage::Attachment.where(record_type: Spree::UserProfile.name, name: 'avatar').select(:record_id)
    profiles.where.not(id: with_avatar).delete_all
  end

  private

  def legacy_users
    columns = FIELDS & Spree::User.column_names
    condition = columns.map { |c| "(#{c} IS NOT NULL AND #{c} <> '')" }.join(' OR ')
    Spree::User.unscoped.where(deleted_at: nil).where(condition)
  end

  def copy_user(user)
    profile = Spree::UserProfile.find_by(user_id: user.id) || Spree::UserProfile.new(user_id: user.id)
    profile.user = user
    fill_blanks(profile, user.attributes.slice(*FIELDS))
    return false unless pending?(profile)

    drop_refused(profile, user)
    return false unless pending?(profile) && profile.valid?

    gained = gained_value?(profile)
    # A savepoint: the migration runs in one transaction, which a failed statement would abort.
    Spree::UserProfile.transaction(requires_new: true) { profile.save! }
    gained
  rescue ActiveRecord::RecordNotUnique
    @logger.warn("[legacy_creator_profiles] user_id=#{user.id} skipped: handle already used")
    false
  end

  # A row whose every legacy value was refused still saves, but isn't a copy. Keep this in step
  # with the migration's "copied N" log line, which the deploy notes tell the operator to check.
  def gained_value?(profile)
    %w[handle bio website links].any? do |field|
      profile.public_send(field).presence != profile.attribute_in_database(field).presence
    end
  end

  def pending?(profile)
    profile.new_record? || profile.changed?
  end

  def fill_blanks(profile, raw)
    profile.handle = raw['display_name'].presence if profile.handle.blank?
    profile.bio = raw['bio'].presence if profile.bio.blank?
    profile.website = raw['website'].presence if profile.website.blank?
    links = profile.links || {}
    missing = SOCIALS.select { |s| raw[s].present? && links[s].blank? }
    profile.links = links.merge(missing.map { |s| [s, raw[s].strip] }.to_h) if missing.any?
  end

  # Puts each refused field back to what the row already holds, and logs which ones went.
  def drop_refused(profile, user)
    return if profile.valid?

    skipped = (profile.errors.attribute_names & %i[handle bio website links name]).flat_map do |field|
      next drop_refused_links(profile) if field == :links

      profile.public_send("#{field}=", profile.attribute_in_database(field))
      [field]
    end
    @logger.warn("[legacy_creator_profiles] user_id=#{user.id} skipped invalid #{skipped.join(', ')}") if skipped.any?
  end

  def drop_refused_links(profile)
    over = profile.links.select { |_key, value| value.to_s.length > Spree::UserProfile::LINK_VALUE_MAX }.keys
    profile.links = profile.links.except(*over)
    over.map { |key| "links.#{key}" }
  end
end
