
class Company < ApplicationRecord
  has_many :users, dependent: :restrict_with_error
  has_many :invitations, dependent: :destroy
  has_many :challenges, dependent: :restrict_with_error

  enum :status, {
    active: "active",
    inactive: "inactive"
  }

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :status, presence: true

  before_validation :generate_slug, if: -> { slug.blank? && name.present? }

  private

  def generate_slug
    self.slug = name.parameterize
  end
end
