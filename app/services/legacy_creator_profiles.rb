# One-off copy of the creator columns on spree_users (display_name, bio, website, socials) into
# spree_user_profiles. Used by the 20261103130000 data migration.
#
# - Only live users with at least one of those columns set, and no profile yet.
# - display_name -> handle, socials -> links; name stays empty (display_name was the handle).
# - A value the profile rules refuse (bad or reserved handle, bio over 280, non-http website) is
#   logged with the user id and left out of the profile; it is never rewritten.
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
    legacy_users.where.not(id: Spree::UserProfile.select(:user_id)).find_each do |user|
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
    raw = user.attributes.slice(*FIELDS)
    attrs = {
      handle: raw['display_name'].presence,
      bio: raw['bio'].presence,
      website: raw['website'].presence,
      links: SOCIALS.each_with_object({}) { |s, h| h[s] = raw[s].strip if raw[s].present? }
    }

    profile = Spree::UserProfile.new(attrs.merge(user_id: user.id))
    profile.user = user
    skipped = []
    3.times do
      break if profile.valid?

      bad = profile.errors.attribute_names & %i[handle bio website links name]
      break if bad.empty?

      bad.each do |field|
        skipped << field
        profile.public_send("#{field}=", field == :links ? {} : nil)
      end
    end
    if skipped.any?
      @logger.warn("[legacy_creator_profiles] user_id=#{user.id} skipped invalid #{skipped.uniq.join(', ')}")
    end
    return false unless profile.valid?

    profile.save!
    true
  rescue ActiveRecord::RecordNotUnique
    @logger.warn("[legacy_creator_profiles] user_id=#{user.id} skipped: handle already used")
    false
  end
end
