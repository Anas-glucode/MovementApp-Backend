module Api
  module V1
    class ActivityHistoriesController < ApplicationController
      # GET /api/v1/activity_history
      def index
        result = ActivityHistoryQueryService.call(
          user: current_user,
          page: params[:page],
          per_page: params[:per_page]
        )

        render json: result, status: :ok
      end
    end
  end
end