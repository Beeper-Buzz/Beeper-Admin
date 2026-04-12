module Spree
  module Api
    module V2
      module Storefront
        module AccountControllerDecorator
          STOREFRONT_CREATOR_ATTRIBUTES = %i[
            display_name bio avatar_url banner_url
            website instagram tiktok youtube soundcloud bandcamp
          ].freeze
          # Intentionally excludes :is_creator — only admins can toggle creator status.

          private

          # Override spree_auth_devise's storefront AccountController decorator
          # to permit self-service creator profile fields. `is_creator` is
          # deliberately NOT included — that field remains admin-only and is
          # only permitted via Spree::Admin::UsersController.
          def spree_user_params
            params.require(:user).permit(
              Spree::PermittedAttributes.user_attributes + STOREFRONT_CREATOR_ATTRIBUTES
            )
          end
        end
      end
    end
  end
end

# spree_auth_devise already prepends this module onto the controller; re-prepend
# here defensively in case load order changes. Prepending an already-prepended
# module is a no-op in Ruby.
Spree::Api::V2::Storefront::AccountController.prepend(
  Spree::Api::V2::Storefront::AccountControllerDecorator
)
