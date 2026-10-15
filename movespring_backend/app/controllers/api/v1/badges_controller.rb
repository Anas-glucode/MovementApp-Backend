module Api
  module V1
    class BadgesController < ApplicationController
      before_action :authenticate_user!

      def index
        badges = Badge.where(company_id: [nil, current_user.company_id])
        user_badge_ids = current_user.user_badges.pluck(:badge_id)

        render json: {
          badges: badges.map { |b|
            {
              id: b.id,
              name: b.name,
              description: b.description,
              category: b.category,
              criteria_type: b.criteria_type,
              criteria_value: b.criteria_value,
              icon_url: b.icon_url,
              earned: user_badge_ids.include?(b.id)
            }
          }
        }, status: :ok
      end

      def user_badges
        earned_badges = current_user.user_badges.includes(:badge, :activity)
        pr_summary = BadgeEvaluationService.new(current_user).call[:personal_records]

        render json: {
          personal_records: pr_summary,
          earned_badges: earned_badges.map { |ub|
            {
              id: ub.id,
              badge_id: ub.badge.id,
              name: ub.badge.name,
              description: ub.badge.description,
              category: ub.badge.category,
              icon_url: ub.badge.icon_url,
              earned_at: ub.earned_at,
              activity_id: ub.activity_id
            }
          }
        }, status: :ok
      end
    end
  end
end