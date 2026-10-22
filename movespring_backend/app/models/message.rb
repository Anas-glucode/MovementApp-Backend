class Message < ApplicationRecord
  belongs_to :user
  belongs_to :chat_room

  validates :body, presence: true, length: { maximum: 1000 }

  after_create_commit :broadcast_to_room

  def as_chat_json
    { id: id, user_id: user_id, user_name: user.name, body: body, created_at: created_at }
  end

  private

  def broadcast_to_room
    ActionCable.server.broadcast("chat_room_#{chat_room_id}", as_chat_json)
  end
end