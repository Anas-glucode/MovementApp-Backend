class InvitationMailer < ApplicationMailer
  after_deliver :mark_invitation_sent

  def invite(invitation, token)
    @invitation = invitation

    # Where the front end's "accept invitation" page lives.
    # In production this MUST be set, otherwise we'd email links that
    # point at localhost.
    base_url = ENV["INVITATION_URL"].presence
    if Rails.env.production? && base_url.blank?
      raise ArgumentError, "INVITATION_URL must be configured in production"
    end

    base_url ||= "http://localhost:3000/accept-invitation"

    # Instance variables (@something) are visible inside the email template.
    # url_encode stops odd characters in the token from breaking the link.
    @accept_url   = "#{base_url}?token=#{ERB::Util.url_encode(token)}"
    @company_name = invitation.company.name
    @expires_at   = invitation.expires_at

    # No body: here. Rails looks for a template file instead:
    # app/views/invitation_mailer/invite.text.erb
    mail(
      to: invitation.email,
      subject: "You've been invited to join #{@company_name}"
    )
  end

  private

  def mark_invitation_sent
    @invitation.update_columns(email_sent_at: Time.current)
  end
end