class ChatRoom < ApplicationRecord
  belongs_to :challenge
  has_many :messages, dependent: :destroy
  has_many :users, through: :messages

  validates :name, presence: true
end