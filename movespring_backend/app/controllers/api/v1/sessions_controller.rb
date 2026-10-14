
module Api
  module V1
    class SessionsController < ApplicationController
skip_before_action :authenticate_user!, only: [:create]
      def create
        email = params[:email].to_s.strip.downcase
        password = params[:password].to_s

        user = User.find_by(email: email)

        if user&.authenticate(password) && user.active? && user.company.active?
          token = TokenService.issue(user)

          render json: {
            message: "Login successful",
            token: token,
            token_type: "Bearer",
            expires_in: TokenService::LIFETIME.to_i,
            user: {
              id: user.id,
              name: user.name,
              email: user.email,
              role: user.role,
              company_id: user.company_id
            }
          }, status: :ok
        else
          render json: {
            error: "Invalid email or password, or account inactive"
          }, status: :unauthorized
        end
      end
    end
  end
end
