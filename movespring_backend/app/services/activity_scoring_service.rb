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

      rules = @scoring_rule_version.rules
      sport_rates = rules.fetch("sport_rates")
      intensity_multipliers = rules.fetch("intensity_multipliers")

      sport_rate = sport_rates.fetch(@activity.activity_type) do
        raise ScoringError, "No scoring rate for this activity type"
      end

      intensity = intensity_band(rules)
      multiplier = intensity_multipliers.fetch(intensity) do
        raise ScoringError, "No multiplier configured for #{intensity}"
      end

      minutes = @activity.duration_seconds / 60.0
      points = (minutes * sport_rate.to_f * multiplier.to_f).round

      ActivityPointAward.create!(
        activity: @activity,
        scoring_rule_version: @scoring_rule_version,
        points: points
      )
    end
  rescue KeyError
    raise ScoringError, "Scoring rules are missing a required setting"
  end

  private

  def intensity_band(rules)
    intensity = @activity.reported_intensity

    return "baseline" if intensity.nil?

    bands = rules.fetch("intensity_bands")
    low_max = bands.fetch("low_max")
    moderate_max = bands.fetch("moderate_max")

    if intensity <= low_max
      "low"
    elsif intensity <= moderate_max
      "moderate"
    else
      "high"
    end
  end
end
