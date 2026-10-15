Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"


namespace :api do
  namespace :v1 do
    post "registrations", to: "registrations#create"
post "sessions", to: "sessions#create"
get "me", to: "profiles#show"
    get "activities", to: "activities#index"
    post "activities", to: "activities#create"
    post "activities/:id/review", to: "activity_reviews#create"
post "invitations", to: "invitations#create"
post "invitations/accept", to: "invitations#accept"
get "employees", to: "employees#index"
patch "employees/:id", to: "employees#update"
patch "employees/:id/deactivate", to: "employees#deactivate"
patch "employees/:id/reactivate", to: "employees#reactivate"
get "company", to: "companies#show"
patch "company", to: "companies#update"
  end
end

end
