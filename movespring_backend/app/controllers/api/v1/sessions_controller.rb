
module Api
  module V1
    class SessionsController < ApplicationController
skip_before_action :authenticate_user!, only: [:create, :refresh, :destroy]

# Max 10 attempts per IP every 3 minutes, like a bouncer who stops
# letting you try keys after too many wrong ones
rate_limit to: 10, within: 3.minutes, only: [:create, :refresh],
  with: -> { render json: { error: "Too many attempts. Try again later." },
                    status: :too_many_requests }
      def create
        email = params[:email].to_s.strip.downcase
        password = params[:password].to_s

        user = User.find_by(email: email)

        if user&.authenticate(password) && user.active? && user.company.active?
          token = TokenService.issue(user)

          render json: {
            message: "Login successful",
            token: token,
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
          }, status: :ok
        else
          render json: {
            error: "Invalid email or password, or account inactive"
          }, status: :unauthorized
        end
      end

      # POST /api/v1/sessions/refresh
      def refresh
        result = RefreshTokenService.rotate(params[:refresh_token])

        unless result
          return render json: { error: "Invalid or expired refresh token" },
                        status: :unauthorized
        end

        render json: {
          token: TokenService.issue(result[:user]),
          token_type: "Bearer",
          expires_in: TokenService::LIFETIME.to_i,
          refresh_token: result[:refresh_token]
        }, status: :ok
      end

      # DELETE /api/v1/sessions
      def destroy
        RefreshTokenService.revoke(params[:refresh_token])
        head :no_content
      end

      # DELETE /api/v1/sessions/all
      def destroy_all
        current_user.refresh_tokens.where(revoked_at: nil)
                    .update_all(revoked_at: Time.current)
        head :no_content
      end
    end
  end
end
