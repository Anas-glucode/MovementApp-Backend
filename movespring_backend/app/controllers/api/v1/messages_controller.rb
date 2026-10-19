module Api
  module V1
    class MessagesController < ApplicationController
      before_action :authenticate_user!

      def index
        chat_room = ChatRoom.find(params[:chat_room_id])
        
        challenge = chat_room.challenge
        unless challenge.company_id == current_user.company_id
          return render json: { error: "Unauthorized access to chat" }, status: :forbidden
        end

        messages = chat_room.messages.includes(:user).order(created_at: :asc).limit(50)

        render json: {
          chat_room_id: chat_room.id,
          messages: messages.map { |m|
            {
              id: m.id,
              user_id: m.user.id,
              user_name: m.user.name,
              body: m.body,
              created_at: m.created_at
            }
          }
        }, status: :ok
      end
    end
  end
end