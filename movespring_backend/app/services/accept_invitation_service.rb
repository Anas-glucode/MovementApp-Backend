
class AcceptInvitationService
  def self.call(token:, name:, password:, password_confirmation:)
    raw_token = token.to_s
    return { errors: ["Invalid or expired invitation"] } if raw_token.blank?

    digest = Digest::SHA256.hexdigest(raw_token)

    invitation = Invitation.find_by(token_digest: digest)

    unless invitation&.usable?
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
        role: "employee",
        status: "active"
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
