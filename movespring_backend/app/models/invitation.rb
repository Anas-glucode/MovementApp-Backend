
class Invitation < ApplicationRecord
  attr_accessor :raw_token

  belongs_to :company
  belongs_to :invited_by, class_name: "User"

  before_validation :normalize_email
  before_validation :generate_token, on: :create

  validates :email, presence: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP }

  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true

  validate :no_duplicate_pending_invitation
  validate :inviter_must_be_company_admin, on: :create
  validate :invitation_expiry_must_be_in_future, on: :create
  validate :email_must_not_belong_to_existing_user, on: :create
  

  scope :pending, -> {
    where(accepted_at: nil, revoked_at: nil)
      .where("expires_at > ?", Time.current)
  }

  def accepted?
    accepted_at.present?
  end

  def revoked?
    revoked_at.present?
  end

  def expired?
    expires_at <= Time.current
  end

  def usable?
    !accepted? && !revoked? && !expired?
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end

  def generate_token
    return if token_digest.present?

    token = SecureRandom.urlsafe_base64(32)
    self.token_digest = Digest::SHA256.hexdigest(token)
    self.raw_token = token
  end

  def no_duplicate_pending_invitation
    return if company_id.blank? || email.blank?

    existing = Invitation.pending.where(company_id: company_id, email: email, accepted_at: nil, revoked_at: nil)

    existing = existing.where.not(id: id) if persisted?

    if existing.exists?
      errors.add(
        :email,
        "already has a pending invitation for this company"
      )
    end
  end

  def inviter_must_be_company_admin
    return if invited_by.blank? || company.blank?

    unless invited_by.company_id == company_id &&
           invited_by.company_admin? &&
           invited_by.active?
      errors.add(
        :invited_by,
        "must be an active administrator of this company"
      )
    end
  end

  def invitation_expiry_must_be_in_future
    return if expires_at.blank?

    if expires_at <= Time.current
      errors.add(:expires_at, "must be in the future")
    end
  end

  def email_must_not_belong_to_existing_user
    return if email.blank?

    if User.exists?(email: email)
      errors.add(:email, "already belongs to a registered user")
    end
  end
end
