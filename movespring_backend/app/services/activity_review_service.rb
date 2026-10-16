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

    if @decision == "rejected" && @reason.blank?
      raise ReviewError, "A reason is required when rejecting an activity"
    end

    Activity.transaction do
      @activity.with_lock do
        if ActivityReview.exists?(activity_id: @activity.id)
          raise ReviewError, "This activity has already been reviewed"
        end

        unless REVIEWABLE_STATUSES.include?(@activity.status)
          raise ReviewError, "This activity is not awaiting review"
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
rescue ActivityScoringService::ScoringError,
       ChallengeActivityScoringService::ScoringError => e
  raise ReviewError, e.message
  end
end
