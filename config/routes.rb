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
