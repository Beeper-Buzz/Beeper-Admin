module Spree
  module Api
    module V1
      class UsersController < Spree::Api::BaseController
        include Swagger::Blocks
        include Response
        include Spree::Api::V1::GlobalHelper
        before_action :authenticate_user, :except => [:sign_up, :sign_in, :profile, :profile_by_handle]

        swagger_path "/users/sign_up" do
          operation :post do
            key :summary, "SIGNUP"
            key :description, "Signing up with email and password"
            key :tags, [
              'Authentication'
            ]
            parameter do
              key :name, 'user[email]'
              key :in, :formData
              key :description, 'email'
              key :required, true
              key :type, :string
            end
            parameter do
              key :name, 'user[password]'
              key :in, :formData
              key :description, 'password'
              key :required, true
              key :type, :string
            end
            parameter do
              key :name, 'user[password_confirmation]'
              key :in, :formData
              key :description, 'password'
              key :required, true
              key :type, :string
            end
            response 200 do
              key :description, "Successfull"
              schema do
                key :'$ref', :user_response
              end
            end
            response 400 do
              key :description, "Error"
              schema do
                key :'$ref', :common_response_model
              end
            end
          end
        end
        swagger_schema :user_response do
          key :required, [:response_code, :response_message]
          property :response_code do
            key :type, :integer
          end
          property :response_message do
            key :type, :string
          end
          property :response_data do
            key :type, :array
            items do
              key :'$ref', :user
            end
          end
        end
        swagger_schema :user do
          property :id do
            key :type, :integer
          end
          property :spree_api_key do
            key :type, :string
          end
          property :email do
            key :type, :string
          end
        end
        def sign_up
          @user = Spree::User.find_by_email(params[:user][:email])

          if @user.present?
            error_model(401, Spree.t('user.error.user_exists'))
            return
          end

          @user = Spree::User.new(user_params)
          if !@user.save
            error_model(400, @user.errors.full_messages.join(','))
            return
          end
          @user.generate_spree_api_key!
          response_data = {
            id: @user.id || 0,
            spree_api_key: @user.spree_api_key || "",
            email: @user.email || ""
          }
          singular_success_model(200,  Spree.t('user.success.sign_up'), response_data)
        end

        swagger_path "/users/sign_in" do
          operation :post do
            key :summary, "Sign in"
            key :description, "Signing in with email and password"
            key :tags, [
              'Authentication'
            ]
            parameter do
              key :name, 'user[email]'
              key :in, :formData
              key :description, 'email'
              key :required, true
              key :type, :string
            end
            parameter do
              key :name, 'user[password]'
              key :in, :formData
              key :description, 'password'
              key :required, true
              key :type, :string
            end
            response 200 do
              key :description, "Successfull"
              schema do
                key :'$ref', :user_response
              end
            end
            response 400 do
              key :description, "Error"
              schema do
                key :'$ref', :common_response_model
              end
            end
          end
        end
        def sign_in
          @user = Spree::User.find_by_email(params[:user][:email])
          if !@user.present? || !@user.valid_password?(params[:user][:password])
            error_model(401, Spree.t('user.error.email_password_unmatch'))
            return
          elsif @user.account_locked?
            # After the password check, so the lock isn't revealed to anyone else. A lock clears
            # the api key, so issuing one here would undo it.
            error_model(403, "This account is locked")
            return
          else
            @user.generate_spree_api_key! if @user.spree_api_key.blank?
            response_data = {
              id: @user.id || 0,
              spree_api_key: @user.spree_api_key || "",
              email: @user.email || ""
            }            
            singular_success_model(200,  Spree.t('user.success.sign_in'), response_data)
          end
        end


        swagger_path "/users/{id}/profile" do
          operation :get do
            key :summary, "GET USER PROFILE"
            key :description, "Get public user profile with optional authentication for extended info"
            key :tags, ['Users']
            
            parameter do
              key :name, :id
              key :in, :path
              key :description, 'User ID'
              key :required, true
              key :type, :integer
            end
            
            parameter do
              key :name, 'token'
              key :in, :query
              key :description, 'Authentication token (optional - provides extended info if viewing own profile)'
              key :required, false
              key :type, :string
            end
            
            response 200 do
              key :description, 'Successful'
              schema do
                key :'$ref', :user_profile_response
              end
            end
            
            response 404 do
              key :description, 'User not found'
            end
          end
        end
        
        swagger_schema :user_profile_response do
          key :required, [:response_code, :response_message]
          property :response_code do
            key :type, :integer
          end
          property :response_message do
            key :type, :string
          end
          property :response_data do
            key :'$ref', :user_profile
          end
        end
        
        swagger_schema :user_profile do
          property :id do
            key :type, :integer
          end
          property :email do
            key :type, :string
          end
          property :first_name do
            key :type, :string
          end
          property :last_name do
            key :type, :string
          end
          property :followers_count do
            key :type, :integer
          end
          property :following_count do
            key :type, :integer
          end
          property :is_following do
            key :type, :boolean
            key :description, 'True if current user is following this profile (requires authentication)'
          end
          property :public_favorites do
            key :type, :array
            items do
              key :'$ref', :favorite_product
            end
          end
        end
        
        swagger_schema :favorite_product do
          property :id do
            key :type, :integer
          end
          property :variant_id do
            key :type, :integer
          end
          property :product_id do
            key :type, :integer
          end
          property :name do
            key :type, :string
          end
          property :slug do
            key :type, :string
          end
          property :price do
            key :type, :string
          end
        end
        
        def profile
          user = Spree::User.find_by_id(params[:id])
          return error_model(404, "User not found") unless user
          render_profile(user)
        end

        def profile_by_handle
          user = Spree::UserProfile.find_by_handle(params[:handle])&.user
          return error_model(404, "User not found") unless user
          render_profile(user)
        end
        
        swagger_path "/users/{id}/follow" do
          operation :post do
            key :summary, "FOLLOW USER"
            key :description, "Follow a user"
            key :tags, ['Users']
            
            parameter do
              key :name, :id
              key :in, :path
              key :description, 'User ID to follow'
              key :required, true
              key :type, :integer
            end
            
            parameter do
              key :name, 'token'
              key :in, :query
              key :description, 'Authentication token'
              key :required, true
              key :type, :string
            end
            
            response 200 do
              key :description, 'Successfully followed user'
              schema do
                key :'$ref', :follow_response
              end
            end
            
            response 400 do
              key :description, 'Error'
            end
            
            response 401 do
              key :description, 'Unauthorized'
            end
          end
        end
        
        swagger_path "/users/{id}/unfollow" do
          operation :post do
            key :summary, "UNFOLLOW USER"
            key :description, "Unfollow a user"
            key :tags, ['Users']
            
            parameter do
              key :name, :id
              key :in, :path
              key :description, 'User ID to unfollow'
              key :required, true
              key :type, :integer
            end
            
            parameter do
              key :name, 'token'
              key :in, :query
              key :description, 'Authentication token'
              key :required, true
              key :type, :string
            end
            
            response 200 do
              key :description, 'Successfully unfollowed user'
              schema do
                key :'$ref', :follow_response
              end
            end
            
            response 400 do
              key :description, 'Error'
            end
            
            response 401 do
              key :description, 'Unauthorized'
            end
          end
        end
        
        swagger_schema :follow_response do
          key :required, [:response_code, :response_message]
          property :response_code do
            key :type, :integer
          end
          property :response_message do
            key :type, :string
          end
          property :response_data do
            property :is_following do
              key :type, :boolean
            end
            property :followers_count do
              key :type, :integer
            end
          end
        end
        
        def follow
          return follow_needs_user unless @current_api_user&.persisted?
          return follow_limit_reached unless Profiles::RateLimit.allow?(@current_api_user, :follow)

          user_to_follow = Spree::User.find_by_id(params[:id])
          unless user_to_follow
            return error_model(404, "User not found")
          end
          
          # Same rule as the visible profile scope: hidden or locked targets don't exist here.
          if user_to_follow.account_locked? || user_to_follow.profile&.hidden?
            return error_model(404, "User not found")
          end

          if @current_api_user.id == user_to_follow.id
            return error_model(400, "Cannot follow yourself")
          end

          if Spree::UserBlock.between?(@current_api_user, user_to_follow)
            return error_model(403, "Cannot follow this user")
          end
          
          # Check if already following
          if UserFollow.following?(@current_api_user, user_to_follow)
            return singular_success_model(200, "Successfully followed user", {
              is_following: true,
              followers_count: user_to_follow.followers.count
            })
          end
          
          # Create follow
          UserFollow.create(follower: @current_api_user, following: user_to_follow)
          
          singular_success_model(200, "Successfully followed user", {
            is_following: true,
            followers_count: user_to_follow.followers.count
          })
        end
        
        def unfollow
          return follow_needs_user unless @current_api_user&.persisted?
          return follow_limit_reached unless Profiles::RateLimit.allow?(@current_api_user, :follow)

          user_to_unfollow = Spree::User.find_by_id(params[:id])
          unless user_to_unfollow
            return error_model(404, "User not found")
          end
          
          # Find and destroy follow relationship
          follow = UserFollow.find_by(follower: @current_api_user, following: user_to_unfollow)
          if follow
            follow.destroy
            singular_success_model(200, "Successfully unfollowed user", {
              is_following: false,
              followers_count: user_to_unfollow.followers.count
            })
          else
            error_model(400, "Not following this user")
          end
        end

        # A guest order token authenticates as an unsaved user, who can't follow anyone.
        def follow_needs_user
          error_model(401, "Sign in to follow users")
        end

        def follow_limit_reached
          error_model(429, "Too many requests. Try again later.")
        end

        def user_params
          params.require(:user).permit(:email, :password, :password_confirmation)
        end

        private

        def render_profile(user)
          # Hidden or locked profiles, and viewers in a block either way, get a 404.
          profile = user.profile
          if profile&.hidden? || user.account_locked? ||
             (@current_api_user&.persisted? && Spree::UserBlock.between?(@current_api_user, user))
            return error_model(404, "User not found")
          end

          # A private profile shows handle, name and photo to anyone but its owner. The blanked
          # keys stay so the web's page keeps working; so do id and is_creator, which it uses.
          restricted = profile.present? && !profile.public_visibility? && @current_api_user&.id != user.id

          public_favorites = restricted ? [] : user.favorites.public_favorites.joins(variant: :product).merge(Spree::Product.publicly_visible).includes(variant: :product).recent.map do |fav|
            {
              id: fav.id,
              variant_id: fav.variant_id,
              product_id: fav.product&.id,
              name: fav.product&.name,
              slug: fav.product&.slug,
              price: fav.variant&.price&.to_s
            }
          end

          is_following = @current_api_user.present? ? UserFollow.following?(@current_api_user, user) : false

          socials = {
            instagram: user.instagram,
            tiktok: user.tiktok,
            youtube: user.youtube,
            soundcloud: user.soundcloud,
            bandcamp: user.bandcamp
          }
          socials = socials.respond_to?(:compact_blank) ? socials.compact_blank : socials.reject { |_, v| v.blank? }
          socials = {} if restricted

          profile_data = {
            # Public profile: anyone can read it. Never put email, billing names,
            # phone or addresses here. The empty keys stay for older web clients.
            id: user.id,
            email: "",
            first_name: "",
            last_name: "",
            display_name: user.display_name,
            is_creator: user.is_creator,
            bio: restricted ? nil : user.bio,
            avatar_url: public_avatar_url(user, profile),
            banner_url: restricted ? nil : user.banner_url,
            website: restricted ? nil : user.website,
            socials: socials,
            followers_count: restricted ? 0 : user.followers.count,
            following_count: restricted ? 0 : user.followings.count,
            is_following: is_following,
            public_favorites: public_favorites,
            recent_streams: user.is_creator && !restricted ? fetch_recent_streams(user) : []
          }

          singular_success_model(200, "User profile retrieved successfully", profile_data)
        end

        # The uploaded avatar, else spree_users.avatar_url when its host is on the allow-list.
        def public_avatar_url(user, profile)
          uploaded = profile && Profiles::Presenter.new(profile, base_url: request.base_url).avatar&.dig(:large)
          uploaded || (user.avatar_url if Profiles.config.avatar_url_allowed?(user.avatar_url))
        end

        def fetch_recent_streams(user)
          return [] unless user.respond_to?(:live_streams)
          user.live_streams
              .where.not(ended_at: nil)
              .order(ended_at: :desc)
              .limit(6)
              .map { |s| { id: s.id, title: s.try(:title), thumbnail_url: s.try(:thumbnail_url), ended_at: s.ended_at } }
        end

      end
    end
  end
end
