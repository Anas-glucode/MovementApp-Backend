class ChatRoomChannel < ApplicationCable::Channel
  def subscribed
    chat_room = find_authorized_room
    return reject unless chat_room

    stream_from "chat_room_#{chat_room.id}"
  end

  def unsubscribed
  end

  def speak(data)
    chat_room = find_authorized_room
    return unless chat_room

    message = chat_room.messages.create(user: current_user, body: data["body"])
    transmit(errors: message.errors.full_messages) unless message.persisted?
  end

  private

  def find_authorized_room
    ChatRoom.joins(:challenge).find_by(
      id: params[:chat_room_id],
      challenges: { company_id: current_user.company_id }
    )
  end
end