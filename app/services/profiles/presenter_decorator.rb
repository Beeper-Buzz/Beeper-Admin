module Profiles
  # Beeper: users whose photo was set on the web only have spree_users.avatar_url (an https URL,
  # no upload). Use it for both sizes when no avatar is attached.
  module PresenterDecorator
    def avatar
      super || legacy_avatar
    end

    private

    def legacy_avatar
      url = user.respond_to?(:avatar_url) ? user.avatar_url.to_s : ''
      return unless url.start_with?('https://')

      Profiles.config.avatar_variants.keys.index_with { url }
    end
  end
end

Profiles::Presenter.prepend(Profiles::PresenterDecorator) unless Profiles::Presenter.include?(Profiles::PresenterDecorator)
