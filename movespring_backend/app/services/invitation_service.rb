
class InvitationService
  EXPIRY_PERIOD = 7.days

  def self.call(invited_by:, email:)
    email = email.to_s.strip.downcase

    invitation = Invitation.new(
      company: invited_by.company,
      invited_by: invited_by,
      email: email,
      expires_at: EXPIRY_PERIOD.from_now
    )

    if invitation.save
      {
        invitation: invitation,
        token: invitation.raw_token
      }
    else
      {
        errors: invitation.errors.full_messages
      }
    end
  end
end
