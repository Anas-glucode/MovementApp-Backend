class Badge < ApplicationRecord
  belongs_to :company, optional: true
  has_many :user_badges, dependent: :destroy
  has_many :users, through: :user_badges

  validates :name, presence: true, uniqueness: { scope: :company_id }
  validates :category, presence: true
  validates :criteria_type, presence: true
  validates :criteria_value, presence: true, numericality: { greater_than_or_equal_to: 0 }
end