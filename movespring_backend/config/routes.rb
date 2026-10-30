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
      post "email_verifications", to: "email_verifications#create"
      post "email_verifications/resend", to: "email_verifications#resend"
      post "sessions", to: "sessions#create"
      post   "sessions/refresh", to: "sessions#refresh"
delete "sessions/all",     to: "sessions#destroy_all"
delete "sessions",         to: "sessions#destroy"
      get "me", to: "profiles#show"
      patch "me", to: "profiles#update"
      patch "me/password", to: "profiles#update_password"
      post "email_changes/confirm", to: "email_changes#confirm"
      get "activities", to: "activities#index"
      post "activities", to: "activities#create"
      post "activities/:id/review", to: "activity_reviews#create"
      post "activity_imports", to: "activity_imports#create"
      post "invitations", to: "invitations#create"
      post "invitations/accept", to: "invitations#accept"
      get "invitations/preview", to: "invitations#preview"
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
         get    "badges",     to: "badges#index"
get    "my_badges",  to: "badges#user_badges"
post   "badges",     to: "badges#create"
patch  "badges/:id", to: "badges#update"
delete "badges/:id", to: "badges#destroy"
get "personal_record_events",
    to: "personal_record_events#index"

get "personal_record_events/unread_count",
    to: "personal_record_events#unread_count"

patch "personal_record_events/read_all",
      to: "personal_record_events#mark_all_read"

patch "personal_record_events/:id/read",
      to: "personal_record_events#mark_read"
      get "notifications",
    to: "notifications#index"

get "notifications/unread_count",
    to: "notifications#unread_count"

patch "notifications/read_all",
      to: "notifications#mark_all_read"

patch "notifications/:id/read",
      to: "notifications#mark_read"
      

      resources :chat_rooms, only: [] do
        resources :messages, only: [:index, :create, :destroy]
      end
    end
  end
end