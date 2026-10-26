module Api
  module V1
    class AnnouncementCommentsController < ApplicationController
      before_action :set_announcement
      before_action :set_comment, only: [ :update, :destroy ]

      def index
        page = [ params[:page].to_i, 1 ].max
        per_page = params[:per_page].to_i
        per_page = 30 unless per_page.positive?
        per_page = [ per_page, 100 ].min
        scope = @announcement.announcement_comments
                              .includes(:user)
                              .order(:created_at, :id)
        total_count = scope.count
        comments = scope.offset((page - 1) * per_page).limit(per_page)

        render json: {
          comments: comments.map(&:as_json),
          pagination: {
            page: page,
            per_page: per_page,
            total_count: total_count,
            total_pages: (total_count.to_f / per_page).ceil
          }
        }, status: :ok
      end

      def create
        comment = @announcement.announcement_comments.new(comment_params)
        comment.user = current_user

        if comment.save
          render json: { comment: comment.as_json }, status: :created
        else
          render json: { errors: comment.errors.full_messages },
                 status: :unprocessable_entity
        end
      end

      def update
        unless @comment.user_id == current_user.id
          return render json: { error: "You can only edit your own comments" },
                        status: :forbidden
        end

        if @comment.update(body: comment_params[:body])
          render json: { comment: @comment.as_json }, status: :ok
        else
          render json: { errors: @comment.errors.full_messages },
                 status: :unprocessable_entity
        end
      end

      def destroy
        unless @comment.user_id == current_user.id || current_user.company_admin?
          return render json: { error: "You can only delete your own comments" },
                        status: :forbidden
        end

        @comment.destroy!
        head :no_content
      end

      private

      def set_announcement
        announcements = current_user.company.announcements
        announcements = announcements.visible_at unless current_user.company_admin?
        @announcement = announcements.find_by(id: params[:announcement_id])
        return if @announcement

        render json: { error: "Announcement not found" }, status: :not_found
      end

      def set_comment
        @comment = @announcement.announcement_comments.find_by(id: params[:id])
        return if @comment

        render json: { error: "Comment not found" }, status: :not_found
      end

      def comment_params
        params.require(:comment).permit(:body, :parent_id)
      end
    end
  end
end
