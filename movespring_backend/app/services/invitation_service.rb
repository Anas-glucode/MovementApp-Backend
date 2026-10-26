
class InvitationService
  EXPIRY_PERIOD = 7.days

  def self.call(invited_by:, email:, role: nil)
    email = email.to_s.strip.downcase
    company = invited_by.company

    invitation = Invitation.new(
      company: company,
      invited_by: invited_by,
      email: email,
      role: role.presence || "employee",
      expires_at: EXPIRY_PERIOD.from_now
    )

    saved = false

    company.with_lock do
      saved = invitation.save
    end

    if saved
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
