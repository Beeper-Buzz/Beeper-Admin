module Profiles
  # Beeper: users whose photo was set on the web only have spree_users.avatar_url (a URL they
  # typed, no upload). Use it for both sizes when no avatar is attached and its host is allowed:
  # the host of an image sees every viewer's IP. See PROFILE_AVATAR_URL_HOSTS.
  module PresenterDecorator
    def avatar
      super || legacy_avatar
    end

    private

    def legacy_avatar
      url = user.respond_to?(:avatar_url) ? user.avatar_url : nil
      return unless Profiles.config.avatar_url_allowed?(url)

      Profiles.config.avatar_variants.keys.index_with { url }
    end
  end
end

Profiles::Presenter.prepend(Profiles::PresenterDecorator) unless Profiles::Presenter.include?(Profiles::PresenterDecorator)
