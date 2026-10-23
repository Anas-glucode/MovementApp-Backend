
module Api
  module V1
    class InvitationsController < ApplicationController
      skip_before_action :authenticate_user!, only: [:accept]
      before_action :require_company_admin!, only: [:create, :index, :destroy, :resend]

      def create
        result = InvitationService.call(
          invited_by: current_user,
          email: invitation_params[:email]
        )

        if result[:invitation]
          response_body = {
            message: "Invitation created successfully",
            invitation: {
              id: result[:invitation].id,
              email: result[:invitation].email,
              expires_at: result[:invitation].expires_at
            }
          }

          response_body[:invitation_token] = result[:token] unless Rails.env.production?

          InvitationMailer.invite(result[:invitation], result[:token]).deliver_later

          render json: response_body, status: :created
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
            token: TokenService.issue(user),
            refresh_token: RefreshTokenService.issue(user),
            token_type: "Bearer",
            expires_in: TokenService::LIFETIME.to_i,
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

      def index
  invitations = current_user.company.invitations.pending.order(created_at: :desc)
  render json: { invitations: invitations.map { |i|
    { id: i.id, email: i.email, expires_at: i.expires_at }
  } }
end

def destroy
  invitation = current_user.company.invitations.pending.find_by(id: params[:id])
  return render json: { error: "Invitation not found" }, status: :not_found unless invitation

  # update_columns skips validations so an old invite can still be
  # cancelled even if the original inviter was deactivated since
  invitation.update_columns(revoked_at: Time.current)
  head :no_content
end

def resend
  old = current_user.company.invitations.pending.find_by(id: params[:id])
  return render json: { error: "Invitation not found" }, status: :not_found unless old

  result = nil
  Invitation.transaction do
    old.update_columns(revoked_at: Time.current)   # cancel the old link
    result = InvitationService.call(invited_by: current_user, email: old.email)
    raise ActiveRecord::Rollback unless result[:invitation]  # undo if new one fails
  end

  if result[:invitation]
    response_body = { message: "Invitation resent" }
    response_body[:invitation_token] = result[:token] unless Rails.env.production?

    InvitationMailer.invite(result[:invitation], result[:token]).deliver_later

    render json: response_body, status: :created
  else
    render json: { errors: result[:errors] }, status: :unprocessable_entity
  end
end

      private

      def require_company_admin!
        return if current_user.company_admin?

        render json: {
          error: "Only company administrators can manage invitations"
        }, status: :forbidden
      end

      def invitation_params
        params.require(:invitation).permit(:email)
      end
    end
  end
end
