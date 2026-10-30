
module Api
  module V1
    class PersonalRecordEventsController < ApplicationController
      DEFAULT_PER_PAGE = 25
      MAX_PER_PAGE = 100

      # GET /api/v1/personal_record_events
      def index
        events = current_user.personal_record_events

        if params[:unread].to_s == "true"
          events = events.where(read_at: nil)
        elsif params[:unread].to_s == "false"
          events = events.where.not(read_at: nil)
        end

        per_page =
          if params[:per_page].present?
            params[:per_page].to_i.clamp(1, MAX_PER_PAGE)
          else
            DEFAULT_PER_PAGE
          end

        page = [params[:page].to_i, 1].max

        total = events.count

        events = events
          .includes(:activity)
          .order(achieved_at: :desc, id: :desc)
          .offset((page - 1) * per_page)
          .limit(per_page)

        render json: {
          personal_record_events: events.map { |event| event_json(event) },
          meta: {
            page: page,
            per_page: per_page,
            total: total
          }
        }, status: :ok
      end

      # GET /api/v1/personal_record_events/unread_count
      def unread_count
        count = current_user.personal_record_events.where(read_at: nil).count

        render json: {
          unread_count: count
        }, status: :ok
      end

      # PATCH /api/v1/personal_record_events/:id/read
      def mark_read
        event = current_user.personal_record_events.find_by(id: params[:id])

        return render json: {
          error: "Personal record event not found"
        }, status: :not_found unless event

        event.update!(read_at: Time.current)

        render json: {
          message: "Personal record notification marked as read",
          personal_record_event: event_json(event)
        }, status: :ok
      end

      # PATCH /api/v1/personal_record_events/read_all
      def mark_all_read
        count = current_user.personal_record_events
                            .where(read_at: nil)
                            .update_all(
                              read_at: Time.current,
                              updated_at: Time.current
                            )

        render json: {
          message: "All personal record notifications marked as read",
          updated_count: count
        }, status: :ok
      end

      private

      def event_json(event)
        {
          id: event.id,
          record_type: event.record_type,
          previous_value: event.previous_value&.to_f,
          new_value: event.new_value.to_f,
          achieved_at: event.achieved_at.iso8601,
          read: event.read_at.present?,
          read_at: event.read_at&.iso8601,
          activity_id: event.activity_id
        }
      end
    end
  end
end
