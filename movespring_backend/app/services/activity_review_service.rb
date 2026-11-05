class ActivityReviewService
  class ReviewError < StandardError; end

  DECISIONS = %w[approved rejected].freeze
  REVIEWABLE_STATUSES = %w[pending under_review].freeze

  def self.call(activity:, reviewer:, decision:, reason: nil)
    new(
      activity: activity,
      reviewer: reviewer,
      decision: decision,
      reason: reason
    ).call
  end

  def initialize(activity:, reviewer:, decision:, reason: nil)
    @activity = activity
    @reviewer = reviewer
    @decision = decision.to_s
    @reason = reason.to_s.strip
  end

  
def call
  unless DECISIONS.include?(@decision)
    raise ReviewError, "Decision must be approved or rejected"
  end

  unless @reviewer&.active? && @reviewer.company&.active? &&
         @reviewer.company_admin?
    raise ReviewError, "An active company administrator is required"
  end

  unless @activity.user.company_id == @reviewer.company_id
    raise ReviewError, "You cannot review activities from another company"
  end

  if @activity.user_id == @reviewer.id
    raise ReviewError, "You cannot review your own activity"
  end

  if @decision == "rejected" && @reason.blank?
    raise ReviewError, "A reason is required when rejecting an activity"
  end

  review = Activity.transaction do
    @activity.with_lock do
      if ActivityReview.exists?(activity_id: @activity.id)
        raise ReviewError, "This activity has already been reviewed"
      end

      unless REVIEWABLE_STATUSES.include?(@activity.status)
        raise ReviewError, "This activity is not awaiting review"
      end

      if @activity.activity_point_award.present? ||
         ChallengeActivityAward.exists?(activity_id: @activity.id)
        raise ReviewError, "This activity already has points and cannot be reviewed"
      end

      scoring_rule_version = nil

      if @decision == "approved"
        scoring_rule_version =
          ScoringRuleVersion
            .where(status: "published")
            .where.not(published_at: nil)
            .order(version_number: :desc)
            .first

        unless scoring_rule_version
          raise ReviewError, "No published scoring rules are available"
        end
      end

      review = ActivityReview.create!(
        activity: @activity,
        reviewer: @reviewer,
        decision: @decision,
        reason: @reason.presence,
        reviewed_at: Time.current
      )

      if @decision == "approved"
        @activity.update!(
          status: "eligible",
          validated_at: Time.current
        )

        ActivityScoringService.call(
          activity: @activity,
          scoring_rule_version: scoring_rule_version
        )

        ChallengeActivityScoringService.call_for_activity(activity: @activity)
      else
        @activity.update!(status: "rejected")
      end

      review
    end
  end

  create_notification(review)

  review
rescue ActivityScoringService::ScoringError,
       ChallengeActivityScoringService::ScoringError => e
  raise ReviewError, e.message
end

private

def create_notification(review)
  approved = @decision == "approved"

  NotificationCreationService.call(
    user: @activity.user,
    notification_type: approved ? "activity_approved" : "activity_rejected",
    title: approved ? "Activity approved!" : "Activity rejected",
    message: if approved
               "Your #{@activity.activity_type.humanize.downcase} activity has been approved."
             else
               "Your #{@activity.activity_type.humanize.downcase} activity was rejected. Reason: #{@reason}"
             end,
    data: {
      activity_id: @activity.id,
      activity_type: @activity.activity_type,
      review_id: review.id,
      decision: @decision,
      reason: @reason.presence
    },
    notifiable: review
  )
rescue StandardError => e
  Rails.logger.error(
    "[Notifications] activity_review=#{review.id} creation failed: #{e.class}: #{e.message}"
  )
  nil
end
end

   