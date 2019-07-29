Rails.application.routes.draw do
  mount Spree::Core::Engine, at: '/'
end

Spree::Core::Engine.add_routes do
  namespace :admin, path: Spree.admin_path do
    resources :messages do
      resources :message_support, only: [:index]
    end

    get "/messages/support" => "messages#message_support"
  end
  
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      resources :messages, only: [:index]
      resources :pages, only: [:index]
    end
  end

end