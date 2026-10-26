module Api
  module V1
    class ProfilesController < ApplicationController
      # The realistic attack on these endpoints is someone with a stolen
      # login token guessing the "current password". So we count attempts
      # PER USER (not per IP), and keep the limit low.
      # (authenticate_user! runs first, so current_user is already known.)
      rate_limit to: 5, within: 3.minutes,
        only: [:update, :update_password],
        by: -> { current_user.id },
        with: -> {
          render json: { error: "Too many attempts. Try again later." },
                 status: :too_many_requests
        }

      # GET /api/v1/me
      def show
        render json: { user: user_json(current_user) }, status: :ok
      end

      # PATCH /api/v1/me
      # Body: { user: { name: "...", email: "..." }, current_password: "..." }
      # current_password is only required when the email is changing.
      def update
        email_changing = requested_email.present? &&
                         requested_email != current_user.email

        # Changing your email is a takeover-risk change (it controls password
        # resets), so we ask for the password again.
        if email_changing && !current_user.authenticate(params[:current_password].to_s)
          return render_wrong_password
        end

        current_user.name = profile_params[:name] if profile_params.key?(:name)

        # We do NOT touch `email` yet. The new address waits in
        # unconfirmed_email until its owner confirms it.
        current_user.unconfirmed_email = requested_email if email_changing

        unless current_user.save
          return render json: { errors: current_user.errors.full_messages },
                        status: :unprocessable_entity
        end

        send_email_change_mails if email_changing

        render json: {
          message: email_changing ?
            "Profile updated. Check your new inbox to confirm the new email address." :
            "Profile updated",
          user: user_json(current_user)
        }, status: :ok
      end

      # PATCH /api/v1/me/password
      # Body: { current_password:, password:, password_confirmation: }
      def update_password
        unless current_user.authenticate(params[:current_password].to_s)
          return render_wrong_password
        end

        # Same guard as password reset: has_secure_password silently ignores
        # "" and skips the match check when confirmation is missing.
        new_password = params[:password].to_s
        confirmation = params[:password_confirmation].to_s

        if new_password.blank?
          return render json: { errors: ["Password can't be blank"] },
                        status: :unprocessable_entity
        end

        if confirmation.blank?
          return render json: { errors: ["Password confirmation can't be blank"] },
                        status: :unprocessable_entity
        end

        # authenticate(new_password) is true when it equals the current one.
        if current_user.authenticate(new_password)
          return render json: { errors: ["New password must be different from your current password"] },
                        status: :unprocessable_entity
        end

        unless current_user.update(password: new_password,
                                   password_confirmation: confirmation)
          return render json: { errors: current_user.errors.full_messages },
                        status: :unprocessable_entity
        end

        # At this point the User callback has already cancelled every refresh
        # token, and every old JWT is dead (the password fragment changed).
        # That logs out all OTHER devices. THIS device would be logged out
        # too, so we hand it brand-new credentials.
        render json: {
          message: "Password updated. All other devices have been logged out.",
          token: TokenService.issue(current_user),
          refresh_token: RefreshTokenService.issue(current_user),
          token_type: "Bearer",
          expires_in: TokenService::LIFETIME.to_i
        }, status: :ok
      end

      private

      def profile_params
        params.require(:user).permit(:name, :email)
      end

      def requested_email
        profile_params[:email].to_s.strip.downcase.presence
      end

      # 422, NOT 401. A 401 tells front ends "your login expired", which
      # often triggers an automatic refresh or logout. A wrong typed password
      # is just a validation error.
      def render_wrong_password
        render json: { error: "Current password is incorrect" },
               status: :unprocessable_entity
      end

      def send_email_change_mails
        token = current_user.generate_token_for(:email_change)

        # 1) Link to the NEW address: "click to confirm".
        EmailChangeMailer.confirm(current_user, token).deliver_later

        # 2) Warning to the OLD address: "someone asked to move your account".
        #    If it wasn't you, you can change your password right away.
        EmailChangeMailer.notice(current_user, current_user.unconfirmed_email).deliver_later
      end

      def user_json(user)
        {
          id: user.id,
          name: user.name,
          email: user.email,
          pending_email: user.unconfirmed_email, # nil when nothing is waiting
          role: user.role,
          company_id: user.company_id
        }
      end
    end
  end
end