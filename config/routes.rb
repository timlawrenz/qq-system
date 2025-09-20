Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # API routes
  namespace :api do
    namespace :v1 do
      # Nested route for creating trades under algorithms
      resources :algorithms, only: [] do
        resources :trades, only: [:create]
      end

      # Individual trade routes
      resources :trades, only: [:show, :update, :destroy]

      # Analysis routes
      resources :analyses, only: [:create, :show]
    end
  end

  # Defines the root path route ("/")
  # root "posts#index"
end
