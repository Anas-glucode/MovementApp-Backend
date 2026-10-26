
class AcceptInvitationService
  def self.call(token:, name:, password:, password_confirmation:)
    invitation = Invitation.find_usable_by_token(token)

    unless invitation
      return { errors: ["Invalid or expired invitation"] }
    end

    user = nil

   Invitation.transaction do
  invitation.lock!
  invitation.reload

  unless invitation.usable?
        raise ActiveRecord::Rollback
      end

      user = invitation.company.users.create!(
        name: name,
        email: invitation.email,
        password: password,
        password_confirmation: password_confirmation,
        role: invitation.role,
        status: "active",
        email_verified_at: Time.current
      )

      invitation.update!(accepted_at: Time.current)
    end

    if user&.persisted? && invitation.reload.accepted?
      { user: user }
    else
      { errors: ["Invalid or expired invitation"] }
    end
  rescue ActiveRecord::RecordInvalid => e
    { errors: e.record.errors.full_messages }
  end
end
