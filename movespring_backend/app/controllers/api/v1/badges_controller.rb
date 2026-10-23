module Api
  module V1
    class BadgesController < ApplicationController
      # Admins manage their company's own badges. Global badges (no company)
      # can't be changed from here.
      before_action :require_company_admin!, only: [:create, :update, :destroy]
      before_action :set_company_badge, only: [:update, :destroy]

      # GET /api/v1/badges  (every badge this person can earn)
      def index
        badges = Badge.where(company_id: [nil, current_user.company_id])
                      .order(:category, :criteria_value, :id)

        earned_at_by_badge = UserBadge.where(user_id: current_user.id)
                                      .pluck(:badge_id, :earned_at)
                                      .to_h

        render json: {
          badges: badges.map { |badge| badge_json(badge, earned_at_by_badge) }
        }, status: :ok
      end

      # GET: only READS. It no longer awards badges, so viewing your badges
      # can never change them. Badges are awarded when an activity is scored.
      def user_badges
        earned = UserBadge.where(user_id: current_user.id)
                          .includes(:badge)
                          .order(earned_at: :desc)

        render json: {
          personal_records: PersonalRecords.call(user: current_user),
          earned_badges: earned.map { |user_badge|
            {
              id: user_badge.id,
              badge_id: user_badge.badge.id,
              name: user_badge.badge.name,
              description: user_badge.badge.description,
              category: user_badge.badge.category,
              icon_url: user_badge.badge.icon_url,
              earned_at: user_badge.earned_at,
              activity_id: user_badge.activity_id
            }
          }
        }, status: :ok
      end

      # POST /api/v1/badges  (admin: a new badge for their own company)
      def create
        badge = Badge.new(badge_params)
        badge.company_id = current_user.company_id

        if badge.save
          render json: { message: "Badge created", badge: badge_json(badge) }, status: :created
        else
          render json: { errors: badge.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # PATCH /api/v1/badges/:id
      def update
        if @badge.update(badge_params)
          render json: { message: "Badge updated", badge: badge_json(@badge) }, status: :ok
        else
          render json: { errors: @badge.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/badges/:id
      def destroy
        if @badge.user_badges.exists?
          return render json: {
            error: "A badge that people have earned cannot be deleted"
          }, status: :unprocessable_entity
        end

        @badge.destroy!
        render json: { message: "Badge deleted" }, status: :ok
      end

      private

      def set_company_badge
        @badge = Badge.find_by(id: params[:id], company_id: current_user.company_id)
        return if @badge

        render json: { error: "Badge not found in your company" }, status: :not_found
      end

      def require_company_admin!
        return if current_user.company_admin?

        render json: { error: "Only company administrators can manage badges" },
               status: :forbidden
      end

      def badge_params
        params.require(:badge).permit(
          :name, :description, :category, :criteria_type, :criteria_value, :icon_url
        )
      end

      # criteria_value is a decimal. Rails would send it as a string
      # ("1000.0"), so it is converted to a plain number for the app.
      def badge_json(badge, earned_at_by_badge = nil)
        json = {
          id: badge.id,
          name: badge.name,
          description: badge.description,
          category: badge.category,
          criteria_type: badge.criteria_type,
          criteria_value: badge.criteria_value.to_f,
          icon_url: badge.icon_url,
          global: badge.global?
        }

        if earned_at_by_badge
          json[:earned] = earned_at_by_badge.key?(badge.id)
          json[:earned_at] = earned_at_by_badge[badge.id]
        end

        json
      end
    end
  end
end