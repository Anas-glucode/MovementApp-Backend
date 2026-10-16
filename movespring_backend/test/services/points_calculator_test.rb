require "test_helper"

class PointsCalculatorTest < ActiveSupport::TestCase
  setup do
    # The same rules your other tests use: walking 1.0, running 1.5,
    # low 0.8, moderate 1.0, high 1.2
    @rules = scoring_rule_versions(:one).rules
  end

  # Builds an activity in memory only. Nothing is saved to the database.
  def build_activity(type:, minutes:, intensity: nil)
    Activity.new(
      activity_type: type,
      duration_seconds: minutes * 60,
      reported_intensity: intensity
    )
  end

  test "scores 30 minutes of walking at baseline as 30 points" do
    points = PointsCalculator.call(
      activity: build_activity(type: "walking", minutes: 30),
      rules: @rules
    )

    assert_equal 30, points
  end

  test "applies the high multiplier for hard effort" do
    # 30 min x running 1.5 x high 1.2 = 54
    points = PointsCalculator.call(
      activity: build_activity(type: "running", minutes: 30, intensity: 8),
      rules: @rules
    )

    assert_equal 54, points
  end

  test "applies the low multiplier for easy effort" do
    # 30 min x walking 1.0 x low 0.8 = 24
    points = PointsCalculator.call(
      activity: build_activity(type: "walking", minutes: 30, intensity: 2),
      rules: @rules
    )

    assert_equal 24, points
  end

  test "raises a clear error for a sport with no rate" do
    error = assert_raises(PointsCalculator::CalculationError) do
      PointsCalculator.call(
        activity: build_activity(type: "curling", minutes: 30),
        rules: @rules
      )
    end

    assert_equal "No scoring rate for this activity type", error.message
  end

  test "raises KeyError when a whole section of the rules is missing" do
    broken_rules = @rules.except("intensity_multipliers")

    assert_raises(KeyError) do
      PointsCalculator.call(
        activity: build_activity(type: "walking", minutes: 30),
        rules: broken_rules
      )
    end
  end
end
