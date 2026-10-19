class ChatRoomChannel < ApplicationCable::Channel
  def subscribed
    chat_room = ChatRoom.find_by(id: params[:chat_room_id])
    
    if chat_room
      stream_from "chat_room_#{chat_room.id}"
    else
      reject
    end
  end

  def unsubscribed

  end

  def speak(data)
    chat_room = ChatRoom.find_by(id: params[:chat_room_id])
    return unless chat_room

    message = chat_room.messages.create(
      user: current_user,
      body: data['body']
    )

    if message.persisted?
      ActionCable.server.broadcast(
        "chat_room_#{chat_room.id}",
        {
          id: message.id,
          user_id: current_user.id,
          user_name: current_user.name,
          body: message.body,
          created_at: message.created_at
        }
      )
    end
  end
end