Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
  
  namespace :api do
    namespace :v1 do
      post "password_resets", to: "password_resets#create"
      patch "password_resets", to: "password_resets#update"
      post "registrations", to: "registrations#create"
      post "sessions", to: "sessions#create"
      post   "sessions/refresh", to: "sessions#refresh"
delete "sessions/all",     to: "sessions#destroy_all"
delete "sessions",         to: "sessions#destroy"
      get "me", to: "profiles#show"
      get "activities", to: "activities#index"
      post "activities", to: "activities#create"
      post "activities/:id/review", to: "activity_reviews#create"
      post "activity_imports", to: "activity_imports#create"
      post "invitations", to: "invitations#create"
      post "invitations/accept", to: "invitations#accept"
      get    "invitations",            to: "invitations#index"
delete "invitations/:id",        to: "invitations#destroy"
post   "invitations/:id/resend", to: "invitations#resend"
      get "employees", to: "employees#index"
      patch "employees/:id/role", to: "employees#change_role"
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
      delete "challenges/:id/join", to: "challenges#leave"
      get "my_challenges", to: "challenges#mine"
         patch "challenges/:id/finalize", to: "challenges#finalize"
   patch "challenges/:id/cancel", to: "challenges#cancel"
      get "challenges/:id/leaderboard", to: "challenges#leaderboard"
      get  "challenges/:challenge_id/teams",   to: "teams#index"
      post "challenges/:challenge_id/teams",   to: "teams#create"
      get  "challenges/:challenge_id/my_team", to: "teams#mine"
         post   "badges",     to: "badges#create"
   patch  "badges/:id", to: "badges#update"
   delete "badges/:id", to: "badges#destroy"
      

      resources :chat_rooms, only: [] do
        resources :messages, only: [:index]
      end
    end
  end
end