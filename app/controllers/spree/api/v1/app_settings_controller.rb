module Spree
  module Api
    module V1
      class AppSettingsController < ActionController::API
        def latest
          setting = AppSetting.latest
          render json: {
            response_code: 200,
            response_data: {
              name: setting.name,
              platform: setting.platform,
              version: setting.version,
              build: setting.build
            }
          }
        end
      end
    end
  end
end
