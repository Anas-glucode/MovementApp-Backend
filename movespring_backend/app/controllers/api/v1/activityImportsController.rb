module Api
  module V1
    # Receives workouts the phone app read from Apple Health or Health Connect.
    #
    # HONEST CAVEAT: the server cannot prove a phone really read HealthKit; a
    # modified app could send made-up workouts. So these are "device-reported",
    # not "verified". What protects you is layered: a required source_record_id
    # (no repeats), plausibility checks, overlap checks against other sources,
    # the daily point cap, and the admin review queue for anything odd.
    #
    # Request:
    #   POST /api/v1/activity_imports
    #   { "source": "healthkit",
    #     "activities": [ { "source_record_id": "...", "activity_type": "running",
    #                       "started_at": "...", "ended_at": "...",
    #                       "duration_seconds": 1800, ... }, ... ] }
    #
    # Each workout succeeds or fails ON ITS OWN, so one bad record doesn't
    # throw away the other 49. The response lists an outcome per workout.
    class ActivityImportsController < ApplicationController
      MAX_BATCH_SIZE = 50
      IMPORT_SOURCES = %w[healthkit health_connect].freeze

      IMPORT_FIELDS = %i[
        source_record_id
        activity_type
        started_at
        ended_at
        duration_seconds
        distance_meters
        steps
        active_calories
        average_heart_rate
        time_zone
      ].freeze

      rate_limit to: 20, within: 1.minute, only: :create,
                 by: -> { current_user.id },
                 with: -> {
                   render json: { error: "Too many import requests. Please slow down." },
                          status: :too_many_requests
                 }

      def create
        source = params[:source].to_s

        unless IMPORT_SOURCES.include?(source)
          return render json: {
            error: "source must be one of: #{IMPORT_SOURCES.join(', ')}"
          }, status: :bad_request
        end

        items = params[:activities]

        unless items.is_a?(Array) && items.any?
          return render json: {
            error: "activities must be a non-empty list"
          }, status: :bad_request
        end

        if items.size > MAX_BATCH_SIZE
          return render json: {
            error: "At most #{MAX_BATCH_SIZE} activities per request"
          }, status: :unprocessable_entity
        end

        results = items.map { |item| import_one(item, source) }

        render json: { results: results }, status: :ok
      end

      private

      def import_one(item, source)
        unless item.is_a?(ActionController::Parameters)
          return { outcome: "error", errors: ["Each activity must be an object"] }
        end

        result = ActivityCreationService.call(
          user: current_user,
          source: source,
          attributes: item.permit(*IMPORT_FIELDS)
        )

        record_id = item[:source_record_id]

        if result[:activity]
          activity = result[:activity]

          {
            source_record_id: record_id,
            outcome: "created",
            activity_id: activity.id,
            status: activity.status,
            review_reason: activity.review_reason,
            points: activity.activity_point_award&.points
          }
        elsif result[:duplicate]
          # Safe to ignore on the app side: we already have this workout.
          { source_record_id: record_id, outcome: "duplicate", errors: result[:errors] }
        else
          { source_record_id: record_id, outcome: "error", errors: result[:errors] }
        end
      end
    end
  end
end