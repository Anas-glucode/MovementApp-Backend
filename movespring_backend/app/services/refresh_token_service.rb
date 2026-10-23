class RefreshTokenService
  LIFETIME = 90.days

  # Creates a new season ticket. Returns the RAW token, which is the only
  # time it exists in readable form. We save just its fingerprint.
  # A new login starts a new family. A refresh keeps the same family.
  def self.issue(user, family_id: SecureRandom.uuid)
    raw = SecureRandom.urlsafe_base64(48)

    RefreshToken.create!(
      user: user,
      token_digest: Digest::SHA256.hexdigest(raw),
      family_id: family_id,
      expires_at: LIFETIME.from_now
    )

    raw
  end

  # Swaps an old ticket for a new one.
  # Returns { user:, refresh_token: } on success, or nil if anything is wrong.
  def self.rotate(raw)
    return nil if raw.blank?

    digest = Digest::SHA256.hexdigest(raw.to_s)
    result = nil

    RefreshToken.transaction do
      # lock stops two requests from swapping the same ticket at once
      record = RefreshToken.lock.find_by(token_digest: digest)
      next if record.nil?

      # A ticket that was already used or cancelled is showing up again.
      # Someone may have copied it, so cancel the whole family.
      if record.revoked_at.present?
        revoke_family(record.family_id)
        next
      end

      next if record.expires_at <= Time.current

      user = record.user

      # Same guest-list check as your authenticate_user!
      unless user.active? && user.company.active?
        revoke_family(record.family_id)
        next
      end

      # Cancel the old ticket, then hand out the new one
      record.update!(revoked_at: Time.current)
      new_raw = issue(user, family_id: record.family_id)

      result = { user: user, refresh_token: new_raw }
    end

    result
  end

  # Logout: the refresh token identifies the session family to cancel.
  def self.revoke(raw)
    return if raw.blank?

    record = RefreshToken.find_by(
      token_digest: Digest::SHA256.hexdigest(raw.to_s)
    )
    revoke_family(record.family_id) if record
  end

  def self.revoke_family(family_id)
    RefreshToken.where(family_id: family_id, revoked_at: nil)
                .update_all(revoked_at: Time.current)
  end
end