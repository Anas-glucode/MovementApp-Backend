module Api
  module V1
    class ActivityReviewsController < ApplicationController
      before_action :require_company_admin!

      def create
        activity = Activity.joins(:user)
                           .where(users: { company_id: current_user.company_id })
                           .find_by(id: params[:id])

        unless activity
          return render json: {
            error: "Activity not found in your company"
          }, status: :not_found
        end

        review = ActivityReviewService.call(
          activity: activity,
          reviewer: current_user,
          decision: params[:decision],
          reason: params[:reason]
        )

        activity.reload
        award = activity.activity_point_award

        render json: {
          message: "Activity review completed successfully",
          review: {
            id: review.id,
            activity_id: review.activity_id,
            decision: review.decision,
            reason: review.reason,
            reviewed_at: review.reviewed_at.iso8601
          },
          activity: {
            id: activity.id,
            status: activity.status
          },
          points_awarded: award&.points
        }, status: :ok
      rescue ActivityReviewService::ReviewError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue ActiveRecord::RecordInvalid => e
        render json: {
          error: e.record.errors.full_messages
        }, status: :unprocessable_entity
      end

      private

      def require_company_admin!
        return if current_user.company_admin?

        render json: {
          error: "Only company administrators can review activities"
        }, status: :forbidden
      end
    end
  end
end
