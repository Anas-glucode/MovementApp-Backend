class RefreshToken < ApplicationRecord
  belongs_to :user

  validates :token_digest, :family_id, :expires_at, presence: true

  # Tickets that are still usable: not cancelled and not expired
  scope :active, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }
end