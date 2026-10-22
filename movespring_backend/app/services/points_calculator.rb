# Turns ONE activity into points, using ONE set of scoring rules.
#
# The formula:
#   minutes x sport rate x intensity multiplier x source multiplier
# rounded to a whole number.
#
# NEW: the "source multiplier". Manual entries are only a claim ("trust me,
# I ran"), so the rules can pay them at a discount, e.g. "manual_multiplier": 0.5
# means a manual workout earns half what the same workout would earn if it
# came from a device. If the rules don't mention it the multiplier is 1.0,
# so existing rules keep working unchanged.
#
# Both ActivityScoringService (personal points) and
# ChallengeActivityScoringService (challenge points) call this, so the maths
# lives in exactly one place. It never saves anything.
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
    (minutes * sport_rate.to_f * multiplier.to_f * source_multiplier).round
  end

  private

  # 1.0 for device data. For manual entries, whatever the rules say (default 1.0).
  def source_multiplier
    return 1.0 unless @activity.source == "manual"

    @rules.fetch("manual_multiplier", 1.0).to_f
  end

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