class User < ApplicationRecord
  belongs_to :company
  has_many :activities, dependent: :destroy
  has_many :challenge_participations, dependent: :destroy
  has_many :joined_challenges, through: :challenge_participations, source: :challenge

  has_secure_password

  enum :role, { employee: "employee", company_admin: "company_admin" }
  enum :status, { active: "active", inactive: "inactive" }

  before_validation :normalize_email

  validates :name, presence: true
  validates :email, presence: true, uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :role, presence: true
  validates :status, presence: true

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end
end
