# Turns ONE activity into points, using ONE set of scoring rules.
#
# The formula: minutes x sport rate x intensity multiplier, rounded to a whole
# number. Both ActivityScoringService (personal points) and
# ChallengeActivityScoringService (challenge points) call this, so the maths
# lives in exactly one place.
#
# It only does arithmetic. It never saves anything and never checks who owns
# the activity or whether a challenge is open. The services do that.
class PointsCalculator
  class CalculationError < StandardError; end

  def self.call(activity:, rules:)
    new(activity: activity, rules: rules).call
  end

  def initialize(activity:, rules:)
    @activity = activity
    @rules = rules
  end

  def call
    # Look up this sport's rate (for example running = 1.5)
    sport_rate = @rules.fetch("sport_rates").fetch(@activity.activity_type) do
      raise CalculationError, "No scoring rate for this activity type"
    end

    # Work out the effort band (low / moderate / high / baseline),
    # then look up its multiplier
    band = intensity_band
    multiplier = @rules.fetch("intensity_multipliers").fetch(band) do
      raise CalculationError, "No multiplier configured for #{band}"
    end

    minutes = @activity.duration_seconds / 60.0
    (minutes * sport_rate.to_f * multiplier.to_f).round
  end

  private

  # Turns the 1-10 effort score into a named band using the cut-offs in the
  # rules. No effort score at all means "baseline".
  def intensity_band
    intensity = @activity.reported_intensity
    return "baseline" if intensity.nil?

    bands = @rules.fetch("intensity_bands")
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
