class EmailVerificationMailer < ApplicationMailer
  def verify(user, token)
    base_url = ENV["EMAIL_VERIFICATION_URL"].presence
    if Rails.env.production? && base_url.blank?
      raise ArgumentError, "EMAIL_VERIFICATION_URL must be configured in production"
    end

    base_url ||= "http://localhost:3000/verify-email"

    @user = user
    @verify_url = "#{base_url}?token=#{ERB::Util.url_encode(token)}"

    mail(to: user.email, subject: "Confirm your email address")
  end
end
