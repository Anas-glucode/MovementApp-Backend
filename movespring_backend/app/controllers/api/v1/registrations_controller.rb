
module Api
  module V1
    class RegistrationsController < ApplicationController
skip_before_action :authenticate_user!, only: [:create]

# Max 10 attempts per IP every 3 minutes, like a bouncer who stops
# letting you try keys after too many wrong ones
rate_limit to: 10, within: 3.minutes, only: :create,
  with: -> { render json: { error: "Too many attempts. Try again later." },
                    status: :too_many_requests }
      def create
        Company.transaction do
          @company = Company.create!(
            name: company_params[:name]
          )

          @user = @company.users.create!(
            name: admin_params[:name],
            email: admin_params[:email],
            password: admin_params[:password],
            password_confirmation: admin_params[:password_confirmation],
            role: "company_admin",
            status: "active"
          )
        end

        # The admin was created with email_verified_at = nil, so they can't log in
        # yet. Mail them their "key card".
        token = @user.generate_token_for(:email_verification)
        EmailVerificationMailer.verify(@user, token).deliver_later

        response_body = {
          message: "Company registered. Check your email to verify your account.",
          company: { id: @company.id, name: @company.name, slug: @company.slug },
          admin: {
            id: @user.id,
            name: @user.name,
            email: @user.email,
            role: @user.role
          }
        }

        # Same pattern as invitations: handy for testing, never exposed in production.
        response_body[:verification_token] = token unless Rails.env.production?

        render json: response_body, status: :created

      rescue ActiveRecord::RecordInvalid => e
        render json: {
          errors: e.record.errors.full_messages
        }, status: :unprocessable_entity
      end

      private

      def company_params
        params.require(:company).permit(:name)
      end

      def admin_params
        params.require(:admin).permit(
          :name,
          :email,
          :password,
          :password_confirmation
        )
      end
    end
  end
end
