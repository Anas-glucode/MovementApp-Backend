
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
  # Fall back to "company" if the name has no Latin letters
  base = name.parameterize.presence || "company"
  candidate = base
  counter = 2

  # Keep adding -2, -3... until nothing else uses the slug
  while Company.exists?(slug: candidate)
    candidate = "#{base}-#{counter}"
    counter += 1
  end

  self.slug = candidate
end

end
