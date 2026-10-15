class ActivityHistoryQueryService
  def self.call(user:, page: 1, per_page: 20)
    new(user: user, page: page, per_page: per_page).call
  end

  def initialize(user:, page:, per_page:)
    @user = user
    @page = [page.to_i, 1].max
    @per_page = [[per_page.to_i, 1].max, 100].min
  end

  def call
    offset = (page - 1) * per_page

    activities = user.activities
                     .includes(:activity_point_award, :activity_review)
                     .order(started_at: :desc)
                     .limit(per_page)
                     .offset(offset)

    total_count = user.activities.count

    {
      activities: activities.map { |act| format_history_item(act) },
      pagination: {
        current_page: page,
        per_page: per_page,
        total_pages: (total_count.to_f / per_page).ceil,
        total_count: total_count
      }
    }
  end

  private

  attr_reader :user, :page, :per_page

  def format_history_item(activity)
    award = activity.activity_point_award
    review = activity.activity_review

    {
      id: activity.id,
      activity_type: activity.activity_type,
      source: activity.source,
      source_record_id: activity.source_record_id,
      started_at: activity.started_at.iso8601,
      ended_at: activity.ended_at.iso8601,
      duration_seconds: activity.duration_seconds,
      metrics: {
        steps: activity.steps,
        distance_meters: activity.distance_meters,
        active_calories: activity.active_calories,
        average_heart_rate: activity.average_heart_rate
      },
      status: activity.status,
      review_details: review ? {
        decision: review.decision,
        reason: review.reason,
        reviewed_at: review.reviewed_at.iso8601
      } : nil,
      points_awarded: award&.points || 0,
      scoring_rule_version_id: award&.scoring_rule_version_id,
      created_at: activity.created_at.iso8601
    }
  end
end