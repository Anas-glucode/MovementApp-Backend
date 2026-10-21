class Api::V1::PasswordResetsController < ApplicationController
  # PasswordResetsController (skip authenticate_user! for both actions)
def create
  user = User.find_by(email: params[:email].to_s.strip.downcase)
  if user&.active?
    PasswordMailer.reset(user, user.generate_token_for(:password_reset)).deliver_later
  end
  # Same answer whether or not the email exists, so nobody can probe for accounts
  render json: { message: "If that email exists, a reset link has been sent" }, status: :ok
end

def update
  user = User.find_by_token_for(:password_reset, params[:token])
  return render json: { error: "Invalid or expired token" }, status: :unprocessable_entity unless user

  if user.update(password: params[:password], password_confirmation: params[:password_confirmation])
    render json: { message: "Password updated" }, status: :ok
  else
    render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
  end
end

  def update
  end
end
