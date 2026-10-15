Rails.application.routes.draw do

  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      post "registrations", to: "registrations#create"
      post "sessions", to: "sessions#create"
      get "me", to: "profiles#show"
      
      get "activities", to: "activities#index"
      post "activities", to: "activities#create"
      
      get "activity_history", to: "activity_histories#index"

      post "activities/:id/review", to: "activity_reviews#create"
      post "invitations", to: "invitations#create"
      post "invitations/accept", to: "invitations#accept"
      
      get "employees", to: "employees#index"
      patch "employees/:id", to: "employees#update"
      patch "employees/:id/deactivate", to: "employees#deactivate"
      patch "employees/:id/reactivate", to: "employees#reactivate"
      
      get "company", to: "companies#show"
      patch "company", to: "companies#update"
      
      get "activity_reviews", to: "activity_reviews#index"
      get "activity_reviews/:id", to: "activity_reviews#show"
      
      get "challenges", to: "challenges#index"
      post "challenges", to: "challenges#create"
      get "challenges/:id", to: "challenges#show"
      patch "challenges/:id", to: "challenges#update"
      patch "challenges/:id/publish", to: "challenges#publish"
      post "challenges/:id/join", to: "challenges#join"
      get "my_challenges", to: "challenges#mine"

      get "dashboard", to: "dashboard#show"
      
      resources :badges, only: [:index] do
        collection do
          get :user_badges
        end
      end
    end
  end
end