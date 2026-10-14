module Api
  module V1
    class ProfilesController < ApplicationController
      def show
        render json: {
          user: {
            id: current_user.id,
            name: current_user.name,
            email: current_user.email,
            role: current_user.role,
            company_id: current_user.company_id
          }
        }, status: :ok
      end
    end
  end
end