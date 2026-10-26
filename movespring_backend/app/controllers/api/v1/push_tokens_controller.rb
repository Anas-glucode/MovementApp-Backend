module Api
  module V1
    class PushTokensController < ApplicationController
      def create
        push_token = PushToken.register_for!(
          user: current_user,
          token: push_token_params[:token]
        )

        if push_token.save
          render json: { message: "Push token registered" }, status: :created
        else
          render json: { errors: push_token.errors.full_messages },
                 status: :unprocessable_entity
        end
      end

      def destroy
        current_user.push_tokens.find_by(token: push_token_params[:token])&.destroy!
        head :no_content
      end

      private

      def push_token_params
        params.require(:push_token).permit(:token)
      end
    end
  end
end
