module Spree
  # Creator profile fields on Spree::User.
  #
  # display_name (the handle), bio, website and the socials now live in spree_user_profiles;
  # these accessors read and write the user's profile so the web's v2 PATCH /account, the admin
  # Users form and the old users/:id/profile and by_handle endpoints keep working on one source
  # of truth. The spree_users columns are no longer written and are dropped in a later cleanup.
  # is_creator, avatar_url and banner_url stay on spree_users (web-only).
  module UserDecorator
    # Kept for reference; the handle rules and reserved names now live in Profiles::HandlePolicy
    # and config/moderation/*reserved_handles.yml.
    DISPLAY_NAME_REGEX = Profiles::HandlePolicy::FORMAT

    SOCIAL_FIELDS = %i[instagram tiktok youtube soundcloud bandcamp].freeze

    # profile attribute => user attribute, for surfacing profile errors on the user.
    PROFILE_ERROR_FIELDS = { handle: :display_name, bio: :bio, website: :website, links: :base, name: :base }.freeze

    def self.prepended(base)
      base.class_eval do
        validates :display_name, presence: true, if: :is_creator?

        validates :avatar_url, :banner_url,
          format: { with: %r{\Ahttps://}, message: "must start with https://" },
          allow_blank: true

        before_validation :normalize_social_handles
        validate :validate_delegated_profile
        after_save :save_delegated_profile
      end
    end

    def display_name
      profile&.handle
    end

    def display_name=(value)
      delegated_profile.handle = value
    end

    def bio
      profile&.bio
    end

    def bio=(value)
      delegated_profile.bio = value
    end

    def website
      profile&.website
    end

    def website=(value)
      delegated_profile.website = value
    end

    SOCIAL_FIELDS.each do |field|
      define_method(field) do
        profile&.links&.[](field.to_s).presence
      end

      define_method("#{field}=") do |value|
        links = (delegated_profile.links || {}).dup
        if value.to_s.strip.empty?
          links.delete(field.to_s)
        else
          links[field.to_s] = value.to_s.strip
        end
        delegated_profile.links = links
      end
    end

    private

    def delegated_profile
      profile || build_profile
    end

    def normalize_social_handles
      return unless profile

      SOCIAL_FIELDS.each do |platform|
        raw = send(platform).to_s.strip
        next if raw.blank?

        cleaned = raw.sub(%r{\Ahttps?://(www\.)?[^/]+/}, "").sub(/\A@/, "").split("/").first
        send("#{platform}=", cleaned) unless cleaned == raw
      end
    end

    def validate_delegated_profile
      return unless profile && (profile.new_record? || profile.changed?)
      return if profile.valid?

      profile.errors.each do |error|
        target = PROFILE_ERROR_FIELDS.fetch(error.attribute, :base)
        message = target == :base ? "#{error.attribute.to_s.humanize} #{error.message}" : error.message
        errors.add(target, message)
      end
    end

    def save_delegated_profile
      return unless profile && (profile.new_record? || profile.changed?)

      profile.user ||= self
      profile.save!
    end
  end
end

Spree::User.prepend(Spree::UserDecorator) unless Spree::User.include?(Spree::UserDecorator)
