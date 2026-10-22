module Api
  module V1
    # Manual activities only. Phone-sync (HealthKit / Health Connect) goes
    # through ActivityImportsController, so a client can never simply
    # declare "I'm a trusted import" on this endpoint.
    class ActivitiesController < ApplicationController
      DEFAULT_PER_PAGE = 25
      MAX_PER_PAGE = 100

      # Built-in Rails rate limiting: like a turnstile that lets 30 people per
      # minute through. Counted per user. It needs a real cache store in
      # production (Rails.cache); the test environment's null store never limits.
      rate_limit to: 30, within: 1.minute, only: :create,
                 by: -> { current_user.id },
                 with: -> {
                   render json: { error: "Too many activities submitted. Please slow down." },
                          status: :too_many_requests
                 }

      # GET /api/v1/activities?page=1&per_page=25&status=eligible&from=...&to=...
      def index
        from, from_ok = parse_time_param(:from)
        to, to_ok = parse_time_param(:to)

        unless from_ok && to_ok
          return render json: {
            error: "from and to must be ISO 8601 date-times"
          }, status: :bad_request
        end

        scope = current_user.activities.includes(:activity_point_award)
        scope = scope.where(status: params[:status]) if Activity::STATUSES.include?(params[:status].to_s)
        scope = scope.where("started_at >= ?", from) if from
        scope = scope.where("started_at <= ?", to) if to

        per_page =
          if params[:per_page].present?
            params[:per_page].to_i.clamp(1, MAX_PER_PAGE)
          else
            DEFAULT_PER_PAGE
          end
        page = [params[:page].to_i, 1].max

        total = scope.count
        activities = scope.order(started_at: :desc, id: :desc)
                          .offset((page - 1) * per_page)
                          .limit(per_page)

        render json: {
          activities: activities.map { |activity| activity_json(activity) },
          meta: { page: page, per_page: per_page, total: total }
        }, status: :ok
      end

      # POST /api/v1/activities  (manual entry)
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
          activity = result[:activity]

          message =
            if activity.status == "under_review"
              "Activity submitted and is waiting for review"
            else
              "Activity submitted successfully"
            end

          render json: {
            message: message,
            activity: activity_json(activity)
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

      # Returns [time_or_nil, ok]. ok is false only when a value WAS supplied
      # but could not be understood, so we can answer 400 instead of ignoring it.
      def parse_time_param(key)
        raw = params[key]
        return [nil, true] if raw.blank?

        [Time.iso8601(raw.to_s), true]
      rescue ArgumentError
        [nil, false]
      end

      def activity_json(activity)
        {
          id: activity.id,
          activity_type: activity.activity_type,
          source: activity.source,
          verification: activity.verification,
          started_at: activity.started_at.iso8601,
          ended_at: activity.ended_at.iso8601,
          duration_seconds: activity.duration_seconds,
          distance_meters: activity.distance_meters,
          steps: activity.steps,
          active_calories: activity.active_calories,
          average_heart_rate: activity.average_heart_rate,
          reported_intensity: activity.reported_intensity,
          status: activity.status,
          review_reason: activity.review_reason,
          validated_at: activity.validated_at&.iso8601,
          points: activity.activity_point_award&.points,
          created_at: activity.created_at.iso8601
        }
      end
    end
  end
end