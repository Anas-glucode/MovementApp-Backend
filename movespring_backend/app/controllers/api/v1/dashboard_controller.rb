module Api
  module V1
    class DashboardController < ApplicationController
      # GET /api/v1/dashboard
      def show
        summary = DashboardSummaryService.call(user: current_user)

        render json: {
          dashboard: summary
        }, status: :ok
      end
    end
  end
end