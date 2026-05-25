Rails.application.config.after_initialize do
  if defined?(Spree::Backend::Config)
    Spree::Backend::Config.configure do |config|
      config.menu_items << Spree::BackendConfiguration::MenuItem.new(
        label: :app_settings,
        icon: 'cog.svg',
        condition: -> { can?(:admin, AppSetting) },
        url: '/admin/app_settings',
        match_path: '/app_settings'
      )
    end
  end
end
