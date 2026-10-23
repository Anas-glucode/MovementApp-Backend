class PasswordMailer < ApplicationMailer
  def reset(user, token)
    base_url = ENV["PASSWORD_RESET_URL"].presence
    if Rails.env.production? && base_url.blank?
      raise ArgumentError, "PASSWORD_RESET_URL must be configured in production"
    end

    base_url ||= "http://localhost:3000/reset-password"
    @reset_url = "#{base_url}?token=#{ERB::Util.url_encode(token)}"

    mail(to: user.email, subject: "Reset your password")
  end
end
