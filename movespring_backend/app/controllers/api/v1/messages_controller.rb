module Api
  module V1
    class MessagesController < ApplicationController
      before_action :authenticate_user!
      before_action :set_chat_room

      def index
        messages = @chat_room.messages.includes(:user).order(created_at: :asc).limit(50)

        render json: {
          chat_room_id: @chat_room.id,
          messages: messages.map(&:as_chat_json)
        }, status: :ok
      end

      def create
        message = @chat_room.messages.build(message_params.merge(user: current_user))

        if message.save
          render json: { message: message.as_chat_json }, status: :created
        else
          render json: { errors: message.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def set_chat_room
        @chat_room = ChatRoom.find_by(id: params[:chat_room_id])
        return render json: { error: "Chat room not found" }, status: :not_found unless @chat_room

        unless @chat_room.challenge.company_id == current_user.company_id
          render json: { error: "Unauthorized access to chat" }, status: :forbidden
        end
      end

      def message_params
        params.require(:message).permit(:body)
      end
    end
  end
end