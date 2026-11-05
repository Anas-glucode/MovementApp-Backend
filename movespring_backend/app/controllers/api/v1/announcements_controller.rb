
module Api
  module V1
    class AnnouncementsController < ApplicationController
      before_action :require_company_admin!,
                    only: [:create, :update, :publish, :archive, :destroy]

      before_action :require_employee!,
                    only: [:mark_read]

      before_action :set_announcement,
                    only: [:show, :update, :publish, :archive, :destroy, :mark_read]

      def index
        announcements = current_user.company.announcements
                                     .includes(:created_by)
                                     .newest_first

        if current_user.employee?
          announcements = announcements.visible_to_employees
        end

        list = announcements.to_a

        reads = if current_user.employee?
                  current_user.announcement_reads
                              .where(announcement_id: list.map(&:id))
                              .index_by(&:announcement_id)
                else
                  {}
                end

        render json: {
          announcements: list.map do |announcement|
            announcement_json(
              announcement,
              read_record: reads[announcement.id]
            )
          end
        }, status: :ok
      end

      def show
        return unless @announcement

        if current_user.employee? &&
   !employee_can_access_announcement?(@announcement)
          return render json: {
            error: "Announcement not found in your company"
          }, status: :not_found
        end

        read_record = current_user.announcement_reads.find_by(
          announcement: @announcement
        )

        render json: {
          announcement: announcement_json(
            @announcement,
            read_record: read_record
          )
        }, status: :ok
      end

      def create
        announcement = current_user.company.announcements.new(
          announcement_params
        )

        announcement.created_by = current_user
        announcement.status = "draft"

        if announcement.save
          render json: {
            message: "Announcement created successfully",
            announcement: announcement_json(announcement)
          }, status: :created
        else
          render json: {
            errors: announcement.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      def update
        return unless @announcement

        unless @announcement.draft?
          return render json: {
            error: "Only draft announcements can be edited"
          }, status: :unprocessable_entity
        end

        if @announcement.update(announcement_params)
          render json: {
            message: "Announcement updated successfully",
            announcement: announcement_json(@announcement)
          }, status: :ok
        else
          render json: {
            errors: @announcement.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      def publish
        return unless @announcement

        begin
          AnnouncementPublishingService.call(
            announcement: @announcement
          )

          render json: {
            message: "Announcement published successfully",
            announcement: announcement_json(@announcement)
          }, status: :ok
        rescue AnnouncementPublishingService::InvalidTransition => e
          render json: {
            error: e.message
          }, status: :unprocessable_entity
        rescue ActiveRecord::RecordInvalid => e
          render json: {
            errors: e.record.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      def archive
        return unless @announcement

        unless @announcement.published?
          return render json: {
            error: "Only published announcements can be archived"
          }, status: :unprocessable_entity
        end

        if @announcement.update(status: "archived")
          render json: {
            message: "Announcement archived successfully",
            announcement: announcement_json(@announcement)
          }, status: :ok
        else
          render json: {
            errors: @announcement.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      def destroy
        return unless @announcement

        unless @announcement.draft?
          return render json: {
            error: "Only draft announcements can be deleted"
          }, status: :unprocessable_entity
        end

        @announcement.destroy!

        render json: {
          message: "Announcement deleted successfully"
        }, status: :ok
      end

      def mark_read
        return unless @announcement

        unless employee_can_access_announcement?(@announcement)
          return render json: {
            error: "Announcement not found in your company"
          }, status: :not_found
        end

       read_record = current_user.announcement_reads.find_or_create_by!(
  announcement: @announcement
) do |record|
  record.read_at = Time.current
end

        render json: {
          message: "Announcement marked as read",
          announcement_id: @announcement.id,
          read_at: read_record.read_at.iso8601
        }, status: :ok
      end

      private

      def employee_can_access_announcement?(announcement)
  return true if announcement.visible_to_employees?

  return false unless announcement.archived?

  current_user.notifications.exists?(
    notification_type: "announcement",
    notifiable: announcement
  )
end

      def set_announcement
        @announcement = current_user.company.announcements.find_by(
          id: params[:id]
        )

        return if @announcement

        render json: {
          error: "Announcement not found in your company"
        }, status: :not_found
      end

      def require_company_admin!
        return if current_user.company_admin?

        render json: {
          error: "Only company administrators can manage announcements"
        }, status: :forbidden
      end

      def require_employee!
        return if current_user.employee?

        render json: {
          error: "Only employees can use this endpoint"
        }, status: :forbidden
      end

      def announcement_params
        params.require(:announcement).permit(:title, :body)
      end

      def announcement_json(announcement, read_record: nil)
        {
          id: announcement.id,
          company_id: announcement.company_id,
          created_by_id: announcement.created_by_id,
          title: announcement.title,
          body: announcement.body,
          status: announcement.status,
          published_at: announcement.published_at&.iso8601,
          read_at: read_record&.read_at&.iso8601,
          created_at: announcement.created_at.iso8601,
          updated_at: announcement.updated_at.iso8601
        }
      end
    end
  end
end
