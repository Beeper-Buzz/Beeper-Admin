module Spree
  module Admin
    module UsersControllerDecorator
      CREATOR_ATTRIBUTES = %i[
        is_creator display_name bio avatar_url banner_url
        website instagram tiktok youtube soundcloud bandcamp
      ].freeze

      private

      def permitted_user_attributes
        super + CREATOR_ATTRIBUTES
      end
    end
  end
end

Spree::Admin::UsersController.prepend(Spree::Admin::UsersControllerDecorator)
