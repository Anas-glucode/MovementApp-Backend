require "test_helper"

class ActivityScoringServiceTest < ActiveSupport::TestCase
  setup do
    @activity = activities(:one)
    @rules = scoring_rule_versions(:one)
  end

  test "calculates points from duration and baseline sport rate" do
    # 30 minutes × walking rate 1.0 × baseline multiplier 1.0
    award = ActivityScoringService.call(
      activity: @activity,
      scoring_rule_version: @rules
    )

    assert_equal 30, award.points
    assert_equal @rules, award.scoring_rule_version
  end

  test "applies the high intensity multiplier" do
    @activity.update!(reported_intensity: 8)

    award = ActivityScoringService.call(
      activity: @activity,
      scoring_rule_version: @rules
    )

    # 30 minutes × walking rate 1.0 × high multiplier 1.2
    assert_equal 36, award.points
  end

  test "rejects an activity that is not eligible" do
    activity = activities(:two)

    assert_equal "pending", activity.status

    assert_raises(ActivityScoringService::ScoringError) do
      ActivityScoringService.call(
        activity: activity,
        scoring_rule_version: @rules
      )
    end

    assert_equal 0, ActivityPointAward.where(activity: activity).count
  end

  test "rejects unpublished scoring rules" do
    draft_rules = ScoringRuleVersion.create!(
      name: "Draft Test Rules",
      version_number: 99,
      status: "draft",
      rules: @rules.rules.deep_dup
    )

    assert_raises(ActivityScoringService::ScoringError) do
      ActivityScoringService.call(
        activity: @activity,
        scoring_rule_version: draft_rules
      )
    end
  end

  test "does not award the same activity twice" do
    first_award = ActivityScoringService.call(
      activity: @activity,
      scoring_rule_version: @rules
    )

    second_award = ActivityScoringService.call(
      activity: @activity,
      scoring_rule_version: @rules
    )

    assert_equal first_award.id, second_award.id
    assert_equal 1, ActivityPointAward.where(activity: @activity).count
  end
end
