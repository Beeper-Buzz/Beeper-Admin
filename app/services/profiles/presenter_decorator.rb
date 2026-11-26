# Beeper: users whose photo was set on the web only have spree_users.avatar_url (a URL they
# typed, no upload). The presenter applies the host rules; see PROFILE_AVATAR_URL_HOSTS.
#
# Written as Profiles::PresenterDecorator, not "module Profiles ... module PresenterDecorator":
# config/application.rb preloads every *_decorator*.rb, and opening "module Profiles" here ran
# before the autoloader loaded app/services/profiles.rb, leaving Profiles without its config.
module Profiles::PresenterDecorator
  private

  def external_avatar_url
    super || (user.avatar_url if user.respond_to?(:avatar_url))
  end
end

Profiles::Presenter.prepend(Profiles::PresenterDecorator) unless Profiles::Presenter.include?(Profiles::PresenterDecorator)
