module Api
  module V1
    class MessagesController < ApplicationController
      before_action :authenticate_user!
      before_action :set_chat_room
      before_action :set_message, only: :destroy

      def index
        messages = @chat_room.messages
                             .includes(:user, media_attachments: :blob)
                             .order(created_at: :desc).limit(50).reverse

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

      def destroy
        unless @message.user_id == current_user.id || current_user.role == "company_admin"
          return render json: { error: "You can only delete your own messages" }, status: :forbidden
        end

        @message.destroy
        head :no_content
      end

      private

      def set_chat_room
        @chat_room = ChatRoom.find_by(id: params[:chat_room_id])
        return render json: { error: "Chat room not found" }, status: :not_found unless @chat_room

        unless @chat_room.challenge.company_id == current_user.company_id
          render json: { error: "Unauthorized access to chat" }, status: :forbidden
        end
      end

      def set_message
        @message = @chat_room.messages.find_by(id: params[:id])
        render json: { error: "Message not found" }, status: :not_found unless @message
      end

      def message_params
        params.require(:message).permit(:body, media: [])
      end
    end
  end
end