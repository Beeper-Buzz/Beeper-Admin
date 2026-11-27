# Loaded early by the decorator glob (config/application.rb). Opening `module Profiles` here first
# would define the constant without app/services/profiles.rb, so Profiles.config would never
# autoload; load that file before reopening the module.
require_dependency Rails.root.join('app/services/profiles').to_s

module Profiles
  # Beeper: users whose photo was set on the web only have spree_users.avatar_url (a URL they
  # typed, no upload). The presenter applies the host rules; see PROFILE_AVATAR_URL_HOSTS.
  module PresenterDecorator
    private

    def external_avatar_url
      super || (user.avatar_url if user.respond_to?(:avatar_url))
    end
  end
end

Profiles::Presenter.prepend(Profiles::PresenterDecorator) unless Profiles::Presenter.include?(Profiles::PresenterDecorator)
