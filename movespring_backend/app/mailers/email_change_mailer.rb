class EmailChangeMailer < ApplicationMailer
  def confirm(user, token)
    base_url = ENV["EMAIL_CHANGE_URL"].presence
    if Rails.env.production? && base_url.blank?
      raise ArgumentError, "EMAIL_CHANGE_URL must be configured in production"
    end
    base_url ||= "http://localhost:3000/confirm-email-change"

    @user = user
    @confirm_url = "#{base_url}?token=#{ERB::Util.url_encode(token)}"

    mail(to: user.unconfirmed_email, subject: "Confirm your new email address")
  end

  def notice(user, new_email)
    @user = user
    @new_email = new_email

    mail(to: user.email, subject: "A change to your email address was requested")
  end
end
