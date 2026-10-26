module Api
  module V1
    class EmailVerificationsController < ApplicationController
      skip_before_action :authenticate_user!

      rate_limit to: 10, within: 3.minutes,
        with: -> {
          render json: { error: "Too many attempts. Try again later." },
                 status: :too_many_requests
        }

      def create
        user = User.find_by_token_for(:email_verification, params[:token].to_s)

        unless user
          return render json: { error: "Invalid or expired verification link" },
                        status: :unprocessable_entity
        end

        user.update!(email_verified_at: Time.current)

        render json: { message: "Email verified. You can now log in." },
               status: :ok
      end

      def resend
        user = User.find_by(email: params[:email].to_s.strip.downcase)

        if user && !user.email_verified? && user.active?
          token = user.generate_token_for(:email_verification)
          EmailVerificationMailer.verify(user, token).deliver_later
        end

        render json: {
          message: "If that account needs verification, a new link has been sent"
        }, status: :ok
      end
    end
  end
end
