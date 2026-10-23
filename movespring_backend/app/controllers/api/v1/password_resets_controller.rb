module Api
  module V1
    class PasswordResetsController < ApplicationController
      skip_before_action :authenticate_user!

      rate_limit to: 10, within: 3.minutes,
        with: -> {
          render json: { error: "Too many attempts. Try again later." },
                 status: :too_many_requests
        }

      def create
        user = User.find_by(email: params[:email].to_s.strip.downcase)
        PasswordMailer.reset(user, user.password_reset_token).deliver_later if user&.active?

        render json: {
          message: "If that email exists, a reset link has been sent"
        }, status: :ok
      end

      def update
        user = User.find_by_password_reset_token(params[:token])
        unless user
          return render json: { error: "Invalid or expired token" },
                        status: :unprocessable_entity
        end

        if user.update(
          password: params[:password],
          password_confirmation: params[:password_confirmation]
        )
          render json: { message: "Password updated" }, status: :ok
        else
          render json: { errors: user.errors.full_messages },
                 status: :unprocessable_entity
        end
      end
    end
  end
end
