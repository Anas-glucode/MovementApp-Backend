class ActivityScoringService
  class ScoringError < StandardError; end

  def self.call(activity:, scoring_rule_version:)
    new(
      activity: activity,
      scoring_rule_version: scoring_rule_version
    ).call
  end

  def initialize(activity:, scoring_rule_version:)
    @activity = activity
    @scoring_rule_version = scoring_rule_version
  end

  def call
    unless @scoring_rule_version.status == "published" &&
           @scoring_rule_version.published_at.present?
      raise ScoringError, "Scoring rules must be published"
    end

    @activity.with_lock do
      existing_award = ActivityPointAward.find_by(activity_id: @activity.id)
      return existing_award if existing_award

      unless @activity.status == "eligible"
        raise ScoringError, "Activity must be eligible before scoring"
      end

      # One shared calculator does the maths for every kind of award
      rules = @scoring_rule_version.rules
      points = PointsCalculator.call(activity: @activity, rules: rules)

      # DAILY CAP: lock this person's row first, so two activities scored at the
      # same moment cannot both slip under the limit.
      @activity.user.lock!

      # Points this person already earned on the same local day
      already_awarded = ActivityPointAward
        .joins(:activity)
        .where(activities: {
          user_id: @activity.user_id,
          started_at: DailyPointCap.day_range(@activity)
        })
        .sum(:points)

      points = DailyPointCap.apply(
        points: points,
        activity: @activity,
        rules: rules,
        already_awarded: already_awarded
      )

      ActivityPointAward.create!(
        activity: @activity,
        scoring_rule_version: @scoring_rule_version,
        points: points
      )
    end
  rescue PointsCalculator::CalculationError => e
    # Keep the services' own error type, with the same messages as before
    raise ScoringError, e.message
  rescue KeyError
    raise ScoringError, "Scoring rules are missing a required setting"
  end
end
