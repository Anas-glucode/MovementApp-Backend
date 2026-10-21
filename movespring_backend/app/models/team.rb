class Team < ApplicationRecord
  belongs_to :challenge
  has_many :team_memberships, dependent: :destroy
  has_many :members, through: :team_memberships, source: :user

  validates :name, presence: true, uniqueness: { scope: :challenge_id }
end