module Api
  module V1
    class ActivityReviewsController < ApplicationController
      before_action :require_company_admin!

      # GET /api/v1/activity_reviews
      def index
        activities = Activity.joins(:user)
                             .includes(:user)
                             .where(
                               users: { company_id: current_user.company_id },
                               status: %w[pending under_review]
                             )
                             .order(created_at: :asc, id: :asc)
                             .limit(100)

        render json: {
          activities: activities.map { |activity| review_queue_json(activity) }
        }, status: :ok
      end

      # GET /api/v1/activity_reviews/:id
      def show
        activity = Activity.joins(:user)
                           .includes(:user)
                           .where(
                             users: { company_id: current_user.company_id },
                             status: %w[pending under_review]
                           )
                           .find_by(id: params[:id])

        unless activity
          return render json: {
            error: "Reviewable activity not found in your company"
          }, status: :not_found
        end

        render json: {
          activity: review_queue_json(activity)
        }, status: :ok
      end

      # POST /api/v1/activities/:id/review
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
          errors: e.record.errors.full_messages
        }, status: :unprocessable_entity
      end

      private

      def review_queue_json(activity)
        {
          id: activity.id,
          employee: {
            id: activity.user.id,
            name: activity.user.name
          },
          activity_type: activity.activity_type,
          source: activity.source,
          started_at: activity.started_at.iso8601,
          ended_at: activity.ended_at.iso8601,
          duration_seconds: activity.duration_seconds,
          steps: activity.steps,
          distance_meters: activity.distance_meters,
          active_calories: activity.active_calories,
          status: activity.status,
          review_reason: activity.review_reason,
          submitted_at: activity.created_at.iso8601
        }
      end

      def require_company_admin!
        return if current_user.company_admin?

        render json: {
          error: "Only company administrators can review activities"
        }, status: :forbidden
      end
    end
  end
end
