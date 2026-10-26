class User < ApplicationRecord
  belongs_to :company
     has_many :user_badges, dependent: :destroy
   has_many :badges, through: :user_badges
  has_many :activities, dependent: :destroy
  has_many :challenge_participations, dependent: :destroy
  has_many :joined_challenges, through: :challenge_participations, source: :challenge
  has_many :messages, dependent: :destroy
  has_many :refresh_tokens, dependent: :destroy

  after_update :revoke_refresh_tokens, if: -> {
    saved_change_to_password_digest? ||
      saved_change_to_email? ||
      (saved_change_to_status? && inactive?)
  }

  has_secure_password

  # Rails builds a signed, expiring token for us. Nothing is stored in the
  # database. The token is "tamper-proof paper" that Rails can verify later.
  #
  # The block's value is baked into the token. Because it includes the email
  # and the verified flag, the token automatically dies if:
  #   - the email address changes, or
  #   - the email has already been verified (so links can't be reused).
  generates_token_for :email_verification, expires_in: 24.hours do
    "#{email}:#{email_verified?}"
  end

  generates_token_for :email_change, expires_in: 24.hours do
    unconfirmed_email
  end

  enum :role, { employee: "employee", company_admin: "company_admin" }
  enum :status, { active: "active", inactive: "inactive" }

  before_validation :normalize_email
  before_validation :normalize_unconfirmed_email

  def email_verified?
    email_verified_at.present?
  end

  def confirm_email_change!
    with_lock do
      return false if unconfirmed_email.blank?

      update!(
        email: unconfirmed_email,
        unconfirmed_email: nil,
        email_verified_at: Time.current
      )
    end
  end

  validates :name, presence: true
  validates :email, presence: true, uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :unconfirmed_email,
            format: { with: URI::MailTo::EMAIL_REGEXP },
            allow_nil: true
  validates :role, presence: true
  validates :status, presence: true
  validates :password, length: { minimum: 8 }, if: -> { password.present? }
  validate :unconfirmed_email_must_be_free, if: -> { unconfirmed_email.present? }

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end

  def normalize_unconfirmed_email
    self.unconfirmed_email = unconfirmed_email.to_s.strip.downcase.presence
  end

  def unconfirmed_email_must_be_free
    if User.where.not(id: id)
           .where("LOWER(email) = ?", unconfirmed_email)
           .exists?
      errors.add(:email, "is already taken")
    end
  end

  def revoke_refresh_tokens
    refresh_tokens.where(revoked_at: nil).update_all(revoked_at: Time.current)
  end
end
