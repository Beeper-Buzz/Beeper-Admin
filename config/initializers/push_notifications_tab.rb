Rails.application.config.after_initialize do
  if defined?(Spree::Backend::Config)
    Spree::Backend::Config.configure do |config|
      config.menu_items << Spree::BackendConfiguration::MenuItem.new(
        label: :push_notifications,
        icon: 'bell.svg',
        condition: -> { can?(:admin, PushNotification) },
        url: '/admin/push_notifications',
        match_path: '/push_notifications'
      )
    end
  end
end
