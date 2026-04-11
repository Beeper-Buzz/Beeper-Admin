module Spree
  module UserDecorator
    DISPLAY_NAME_REGEX = /\A[a-z0-9_]{3,30}\z/

    RESERVED_SLUGS = %w[
      cart checkout login signup account browse about terms privacy home
      reset-password thank-you update-email update-password api admin
      tv user images fonts static assets _next creator-application
    ].freeze

    def self.prepended(base)
      base.class_eval do
        validates :display_name,
          format: { with: DISPLAY_NAME_REGEX, message: "must be 3-30 lowercase letters, numbers, or underscores" },
          exclusion: { in: RESERVED_SLUGS, message: "is reserved" },
          uniqueness: { case_sensitive: false, allow_nil: true },
          allow_nil: true

        validates :display_name, presence: true, if: :is_creator?

        validates :avatar_url, :banner_url,
          format: { with: %r{\Ahttps://}, message: "must start with https://" },
          allow_blank: true

        validates :website,
          format: { with: %r{\Ahttps?://}, message: "must start with http:// or https://" },
          allow_blank: true

        before_validation :normalize_display_name
        before_validation :normalize_social_handles
      end
    end

    private

    def normalize_display_name
      return if display_name.blank?
      self.display_name = display_name.to_s.downcase.strip
    end

    def normalize_social_handles
      %i[instagram tiktok youtube soundcloud bandcamp].each do |platform|
        raw = send(platform).to_s.strip
        next if raw.blank?
        cleaned = raw.sub(%r{\Ahttps?://(www\.)?[^/]+/}, "").sub(/\A@/, "").split("/").first
        send("#{platform}=", cleaned)
      end
    end
  end
end

Spree::User.prepend(Spree::UserDecorator) unless Spree::User.include?(Spree::UserDecorator)
