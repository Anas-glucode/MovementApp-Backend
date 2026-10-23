
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

        render json: {
          message: "Company registered successfully",
          company: {
            id: @company.id,
            name: @company.name,
            slug: @company.slug
          },
          admin: {
            id: @user.id,
            name: @user.name,
            email: @user.email,
            role: @user.role
          }
        }, status: :created

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
