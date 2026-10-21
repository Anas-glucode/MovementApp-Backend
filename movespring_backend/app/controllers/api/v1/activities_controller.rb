module Api
  module V1
    class ActivitiesController < ApplicationController
      def index
        activities = current_user.activities.includes(:activity_point_award)
                                 .order(started_at: :desc)
                                 .limit(100)

        render json: {
          activities: activities.map { |activity| activity_json(activity) }
        }, status: :ok
      end

      def create
        unless params[:activity].is_a?(ActionController::Parameters)
          return render json: {
            error: "Activity details are required"
          }, status: :bad_request
        end

        result = ActivityCreationService.call(
          user: current_user,
          source: "manual",
          attributes: activity_params
        )

        if result[:activity]
          render json: {
            message: "Activity submitted successfully",
            activity: activity_json(result[:activity])
          }, status: :created
        else
          render json: {
            errors: result[:errors]
          }, status: :unprocessable_entity
        end
      end

      private

      def activity_params
        params.require(:activity).permit(
          :activity_type,
          :started_at,
          :ended_at,
          :distance_meters,
          :steps,
          :active_calories,
          :reported_intensity,
          :time_zone
        )
      end

      def activity_json(activity)
        {
          id: activity.id,
          activity_type: activity.activity_type,
          source: activity.source,
          started_at: activity.started_at.iso8601,
          ended_at: activity.ended_at.iso8601,
          duration_seconds: activity.duration_seconds,
          distance_meters: activity.distance_meters,
          steps: activity.steps,
          active_calories: activity.active_calories,
          average_heart_rate: activity.average_heart_rate,
          status: activity.status,
          review_reason: activity.review_reason,
          validated_at: activity.validated_at,
          points: activity.activity_point_award&.points,
          created_at: activity.created_at.iso8601
        }
      end
    end
  end
end
