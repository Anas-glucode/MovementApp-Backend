module Api
  module V1
    class AnnouncementsController < ApplicationController
      before_action :require_company_admin!, only: [ :create, :update, :destroy ]
      before_action :set_company_announcement, only: [ :update, :destroy ]

      def index
        announcements = current_user.company.announcements
        if current_user.company_admin?
          announcements = announcements.order(starts_at: :desc, id: :desc)
        else
          announcements = announcements.visible_at
                                         .where.not(
                                           id: current_user.announcement_dismissals.select(:announcement_id)
                                         )
                                         .order(starts_at: :desc, id: :desc)
        end

        render json: {
          announcements: announcements.map { |announcement| announcement_json(announcement) }
        }, status: :ok
      end

      def create
        announcement = current_user.company.announcements.new(announcement_params)
        announcement.starts_at ||= Time.current

        if announcement.save
          render json: {
            message: "Announcement created successfully",
            announcement: announcement_json(announcement)
          }, status: :created
        else
          render json: { errors: announcement.errors.full_messages },
                 status: :unprocessable_entity
        end
      end

      def update
        if @announcement.update(announcement_params)
          render json: {
            message: "Announcement updated successfully",
            announcement: announcement_json(@announcement)
          }, status: :ok
        else
          render json: { errors: @announcement.errors.full_messages },
                 status: :unprocessable_entity
        end
      end

      def destroy
        @announcement.destroy!
        render json: { message: "Announcement deleted successfully" }, status: :ok
      end

      def dismiss
        announcement = current_user.company.announcements
                                   .visible_at
                                   .find_by(id: params[:id])
        return render json: { error: "Announcement not found" }, status: :not_found unless announcement

        current_user.announcement_dismissals.find_or_create_by!(
          announcement: announcement
        )

        render json: { message: "Announcement dismissed" }, status: :ok
      end

      private

      def set_company_announcement
        @announcement = current_user.company.announcements.find_by(id: params[:id])
        return if @announcement

        render json: { error: "Announcement not found in your company" },
               status: :not_found
      end

      def require_company_admin!
        return if current_user.company_admin?

        render json: {
          error: "Only company administrators can manage announcements"
        }, status: :forbidden
      end

      def announcement_params
        params.require(:announcement).permit(:title, :message, :starts_at, :ends_at, :active)
      end

      def announcement_json(announcement)
        {
          id: announcement.id,
          title: announcement.title,
          message: announcement.message,
          starts_at: announcement.starts_at,
          ends_at: announcement.ends_at,
          active: announcement.active?,
          visible: announcement.visible_at?,
          created_at: announcement.created_at,
          updated_at: announcement.updated_at
        }
      end
    end
  end
end
