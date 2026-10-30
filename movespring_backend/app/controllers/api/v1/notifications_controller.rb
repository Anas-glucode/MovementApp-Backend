module Api
  module V1
    class NotificationsController < ApplicationController
      DEFAULT_PER_PAGE = 25
      MAX_PER_PAGE = 100

      # GET /api/v1/notifications
      def index
        notifications = current_user.notifications

        if params[:unread].to_s == "true"
          notifications = notifications.unread
        elsif params[:unread].to_s == "false"
          notifications = notifications.read
        end

        per_page =
          if params[:per_page].present?
            params[:per_page].to_i.clamp(1, MAX_PER_PAGE)
          else
            DEFAULT_PER_PAGE
          end

        page = [params[:page].to_i, 1].max
        total = notifications.count

        notifications = notifications
          .newest_first
          .offset((page - 1) * per_page)
          .limit(per_page)

        render json: {
          notifications: notifications.map { |notification| notification_json(notification) },
          meta: {
            page: page,
            per_page: per_page,
            total: total
          }
        }, status: :ok
      end

      # GET /api/v1/notifications/unread_count
      def unread_count
        count = current_user.notifications.unread.count

        render json: {
          unread_count: count
        }, status: :ok
      end

      # PATCH /api/v1/notifications/:id/read
      def mark_read
        notification = current_user.notifications.find_by(id: params[:id])

        return render json: {
          error: "Notification not found"
        }, status: :not_found unless notification

        notification.mark_as_read!

        render json: {
          message: "Notification marked as read",
          notification: notification_json(notification)
        }, status: :ok
      end

      # PATCH /api/v1/notifications/read_all
      def mark_all_read
        now = Time.current

        count = current_user.notifications
                             .unread
                             .update_all(
                               read_at: now,
                               updated_at: now
                             )

        render json: {
          message: "All notifications marked as read",
          updated_count: count
        }, status: :ok
      end

      private

      def notification_json(notification)
        {
          id: notification.id,
          notification_type: notification.notification_type,
          title: notification.title,
          message: notification.message,
          data: notification.data,
          notifiable_type: notification.notifiable_type,
          notifiable_id: notification.notifiable_id,
          read: notification.read?,
          read_at: notification.read_at&.iso8601,
          created_at: notification.created_at.iso8601
        }
      end
    end
  end
end