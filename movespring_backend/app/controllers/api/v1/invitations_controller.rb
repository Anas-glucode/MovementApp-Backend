
module Api
  module V1
    class InvitationsController < ApplicationController
      skip_before_action :authenticate_user!, only: [:accept]

      def create
        unless current_user.company_admin?
          return render json: {
            error: "Only company administrators can invite employees"
          }, status: :forbidden
        end

        result = InvitationService.call(
          invited_by: current_user,
          email: invitation_params[:email]
        )

        if result[:invitation]
          render json: {
            message: "Invitation created successfully",
            invitation: {
              id: result[:invitation].id,
              email: result[:invitation].email,
              expires_at: result[:invitation].expires_at
            },
            invitation_token: result[:token]
          }, status: :created
        else
          render json: {
            errors: result[:errors]
          }, status: :unprocessable_entity
        end
      end

      def accept
        result = AcceptInvitationService.call(
          token: params[:token],
          name: params[:name],
          password: params[:password],
          password_confirmation: params[:password_confirmation]
        )

        if result[:user]
          user = result[:user]

          render json: {
            message: "Invitation accepted successfully",
            user: {
              id: user.id,
              name: user.name,
              email: user.email,
              role: user.role,
              company_id: user.company_id
            }
          }, status: :created
        else
          render json: {
            errors: result[:errors]
          }, status: :unprocessable_entity
        end
      end

      private

      def invitation_params
        params.require(:invitation).permit(:email)
      end
    end
  end
end
