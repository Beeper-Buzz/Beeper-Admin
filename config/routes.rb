Rails.application.routes.draw do
  # This line mounts Spree's routes at the root of your application.
  mount Spree::Core::Engine, at: '/'

  resources :apidocs, only: [:index] do
    collection do
      get 'swagger_ui'
    end
  end
end

Spree::Core::Engine.add_routes do
  namespace :admin, path: Spree.admin_path do
    resources :messages do      
      collection do
        get :conversation
        get :conversations
      end
      collection do
        get :conversation
        get :conversations
      end
      resources :message_support, only: [:index]
    end 

    get "/messages/support" => "messages#message_support"
    get "/menu_items/show_menu_item" => "menu_items#show_menu_item"
    get "/menu_locations/show_menu_location" => "menu_locations#show_menu_location"

    resources :live_stream do
      collection do
        get :generate_playback
      end
    end
    
    resources :homepage_sections do
      member do
        post :move_up
        post :move_down
        patch :toggle_visibility
      end
    end
    
    resources :contacts
    resources :app_settings, only: [:index, :create, :destroy]

    resources :products, only: [] do
      resources :product_videos, except: :show do
        collection do
          post :update_positions
        end
      end
    end

    resources :threads do
      member do
        get :conversation
      end
    end

    resources :push_notifications, only: [:index] do
      collection do
        post :send_notification
        post :notify_product
      end
    end

    resources :menu_locations do
      resources :menu_items
    end
    resources :menu_items, except: :show do
      member do
        get :children
      end
    end

    # Profile moderation.
    resources :content_reports, only: [:index, :show] do
      member do
        post :dismiss
        post :hide_profile
        post :remove_photo
        post :clear_bio
        post :lock_account
      end
    end
    resources :user_profiles, only: [] do
      member do
        post :hide
        post :unhide
      end
    end
    resources :users, only: [] do
      resource :account_lock, only: [:create, :destroy]
    end
  end
  namespace :admin do
    resources :menu_items, except: :show do
      member do
        get :children
      end
    end
  end

  namespace :api, constraints: { format: 'json' } do
    namespace :v1 do
      resources :live_stream do
        member do
          post :add_watcher
          post :remove_watcher
        end
      end
      resources :homepage_sections
      resources :favorites, only: [:index, :destroy] do
        collection do
          post :toggle
          get :check
        end
        member do
          post :toggle_public
        end
      end
      resources :users do
        collection do
          post :sign_up
          post :sign_in
        end
        member do
          get :profile
          post :follow
          post :unfollow
        end
      end
      get "users/by_handle/:handle/profile", to: "users#profile_by_handle"
      resources :pages, only: [:index, :show], controller: 'pages', param: :slug
      # The signed-in user deletes their own account (OAuth bearer required).
      resource :account, only: [:destroy], controller: 'account', defaults: { format: 'json' }
      # Public profiles, follows, blocks and reports.
      defaults format: 'json' do
        resource :profile, only: [:show, :update], controller: 'profile' do
          put :avatar, action: :update_avatar
          delete :avatar, action: :destroy_avatar
        end
        resources :profiles, only: [:show], param: :handle do
          collection do
            get :handle_available
          end
          member do
            post :follow
            delete :follow, action: :unfollow
          end
        end
        resources :blocks, only: [:index, :create, :destroy], param: :handle
        resources :reports, only: [:create]
      end
      resources :contacts
      resources :messages
      resources :push_subscriptions, only: [:create, :destroy]
      resources :app_settings, only: [] do
        collection do
          get :latest
        end
      end
      resources :threads
      resources :menu_items do
        member do
          get :children
        end
      end
      resources :menu_locations do
        member do
          get :menu_items
        end
      end
    end

    namespace :v2 do
      namespace :storefront do
        resource :store, only: [:show], path: 'default_store', as: :default_store, controller: 'store'
      end
    end
  end
end

# App feedback: the app's endpoint and the admin's Feedback tab.
Spree::Core::Engine.add_routes do
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      post :feedback, to: 'feedback#create', as: :feedback
    end
  end

  namespace :admin, path: Spree.admin_path do
    resources :app_feedbacks, path: 'feedback', only: %i[index show update] do
      collection { post :bulk_archive }
    end
  end
end

# Device firmware releases: the clients' check and reports, CI's draft upload, and the admin's
# Firmware tab. See app/services/firmware.rb.
Spree::Core::Engine.add_routes do
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      get 'firmware/check', to: 'firmware/checks#show', as: :firmware_check
      post 'firmware/reports', to: 'firmware/reports#create', as: :firmware_reports
      post 'admin/firmware/bundles', to: 'firmware/uploads#create', as: :firmware_uploads
    end
  end

  namespace :admin, path: Spree.admin_path do
    resources :firmware_bundles, path: 'firmware' do
      member do
        post :publish
        post :pause
        post :revoke
      end
      resources :firmware_images, path: 'images', only: %i[create destroy]
    end
  end
end

# Digital library (ownership, signed download links, free claims) and direct uploads.
Spree::Core::Engine.add_routes do
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      get 'library', to: 'library#index', as: :library
      post 'library/claim', to: 'library#claim', as: :library_claim
      post 'library/:ownership_id/links', to: 'library#links', as: :library_links
      post 'uploads', to: 'uploads#create', as: :uploads
    end
  end
end

# Admin: the "Digital asset" tab on products and the ownership panel on users.
Spree::Core::Engine.add_routes do
  namespace :admin, path: Spree.admin_path do
    resources :products, only: [] do
      resources :digital_assets, except: :show do
        member do
          post :publish
          post :retire
          delete 'files/:attachment_id', action: :remove_file, as: :remove_file
        end
      end
    end
    resources :users, only: [] do
      resources :digital_ownerships, only: :create do
        member { post :revoke }
      end
    end
  end
end
