module Api
  module V1
    class EmailChangesController < ApplicationController
      skip_before_action :authenticate_user!

      rate_limit to: 10, within: 3.minutes,
        with: -> {
          render json: { error: "Too many attempts. Try again later." },
                 status: :too_many_requests
        }

      def confirm
        user = User.find_by_token_for(:email_change, params[:token].to_s)

        unless user
          return render json: { error: "Invalid or expired confirmation link" },
                        status: :unprocessable_entity
        end

        begin
          confirmed = user.confirm_email_change!
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
          return render json: {
            error: "That email address is no longer available"
          }, status: :unprocessable_entity
        end

        unless confirmed
          return render json: { error: "Invalid or expired confirmation link" },
                        status: :unprocessable_entity
        end

        render json: {
          message: "Email address updated. Please log in again."
        }, status: :ok
      end
    end
  end
end
