class User < ApplicationRecord
  belongs_to :company
     has_many :user_badges, dependent: :destroy
   has_many :badges, through: :user_badges
  has_many :activities, dependent: :destroy
  has_many :challenge_participations, dependent: :destroy
  has_many :joined_challenges, through: :challenge_participations, source: :challenge
  has_many :messages, dependent: :destroy
  has_many :refresh_tokens, dependent: :destroy
  has_many :announcement_dismissals, dependent: :destroy
  has_many :dismissed_announcements, through: :announcement_dismissals,
                                    source: :announcement

  after_update :revoke_refresh_tokens, if: -> {
  saved_change_to_password_digest? || (saved_change_to_status? && inactive?)
}

  has_secure_password

  enum :role, { employee: "employee", company_admin: "company_admin" }
  enum :status, { active: "active", inactive: "inactive" }

  before_validation :normalize_email

  validates :name, presence: true
  validates :email, presence: true, uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :role, presence: true
  validates :status, presence: true
  validates :password, length: { minimum: 8 }, if: -> { password.present? }

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end

  def revoke_refresh_tokens
  refresh_tokens.where(revoked_at: nil).update_all(revoked_at: Time.current)
end
end
