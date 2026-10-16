require "test_helper"
require "securerandom"

class ChallengeActivityScoringServiceTest < ActiveSupport::TestCase
  setup do
    @company = create_company("Scoring Test Company")
    @employee = create_user(@company)
    @rules = scoring_rule_versions(:one)

  @challenge = Challenge.create!(
  company: @company,
  scoring_rule_version: @rules,
  name: "Scoring Test Challenge",
  description: "Challenge scoring service test",
  starts_at: 2.days.from_now,
  ends_at: 9.days.from_now,
  status: "published"
)

ChallengeParticipation.create!(
  challenge: @challenge,
  user: @employee
)

# The employee joins before the challenge starts.
# Move it into its active period for scoring tests.
@challenge.update_columns(
  starts_at: 2.days.ago,
  ends_at: 2.days.from_now,
  status: "active"
)

    @activity = create_activity(
      user: @employee,
      started_at: 1.hour.ago,
      ended_at: 30.minutes.ago,
      status: "eligible"
    )
  end

  test "calculates points using the challenge scoring version" do
    award = ChallengeActivityScoringService.call(
      challenge: @challenge,
      activity: @activity
    )

    assert_equal 30, award.points
    assert_equal @challenge, award.challenge
    assert_equal @rules, award.scoring_rule_version
  end

  test "uses the challenge rules rather than the latest published version" do
    newer_rules = @rules.rules.deep_dup
    newer_rules["sport_rates"]["walking"] = 2.0

    another_version = ScoringRuleVersion.create!(
      name: "Newer Test Rules",
      version_number: ScoringRuleVersion.maximum(:version_number).to_i + 1,
      status: "published",
      published_at: Time.current,
      rules: newer_rules
    )

    # Publishing a newer version must not change this challenge's rules.
    assert_equal @rules.id, @challenge.reload.scoring_rule_version_id
    assert_equal another_version.id, ScoringRuleVersion.order(:version_number).last.id

    award = ChallengeActivityScoringService.call(
      challenge: @challenge,
      activity: @activity
    )

    assert_equal 30, award.points
    assert_equal @rules.id, award.scoring_rule_version_id
  end

  test "continues to use a previously published version after retirement" do
    @rules.update!(status: "retired")

    award = ChallengeActivityScoringService.call(
      challenge: @challenge,
      activity: @activity
    )

    assert_equal 30, award.points
    assert_equal @rules.id, award.scoring_rule_version_id
  end

  test "rejects an activity outside the challenge dates" do
    @activity.update!(
      started_at: @challenge.starts_at - 2.hours,
      ended_at: @challenge.starts_at - 1.hour,
      duration_seconds: 3600
    )

    assert_raises(ChallengeActivityScoringService::ScoringError) do
      ChallengeActivityScoringService.call(
        challenge: @challenge,
        activity: @activity
      )
    end

    assert_equal 0, ChallengeActivityAward.where(
      challenge: @challenge,
      activity: @activity
    ).count
  end

  test "rejects an activity that is not eligible" do
    @activity.update!(status: "pending")

    assert_raises(ChallengeActivityScoringService::ScoringError) do
      ChallengeActivityScoringService.call(
        challenge: @challenge,
        activity: @activity
      )
    end

    assert_equal 0, ChallengeActivityAward.where(
      challenge: @challenge,
      activity: @activity
    ).count
  end

  test "rejects an activity from a user who has not joined the challenge" do
    another_employee = create_user(@company)
    activity = create_activity(
      user: another_employee,
      started_at: 1.hour.ago,
      ended_at: 30.minutes.ago,
      status: "eligible"
    )

    assert_raises(ChallengeActivityScoringService::ScoringError) do
      ChallengeActivityScoringService.call(
        challenge: @challenge,
        activity: activity
      )
    end

    assert_equal 0, ChallengeActivityAward.where(activity: activity).count
  end

  test "does not award the same activity twice for one challenge" do
    first_award = ChallengeActivityScoringService.call(
      challenge: @challenge,
      activity: @activity
    )

    second_award = ChallengeActivityScoringService.call(
      challenge: @challenge,
      activity: @activity
    )

    assert_equal first_award.id, second_award.id
    assert_equal 1, ChallengeActivityAward.where(
      challenge: @challenge,
      activity: @activity
    ).count
  end

  private

  def create_company(name)
    Company.create!(
      name: name,
      slug: "#{name.parameterize}-#{SecureRandom.hex(4)}",
      status: "active"
    )
  end

  def create_user(company)
    User.create!(
      company: company,
      name: "Test Employee #{SecureRandom.hex(3)}",
      email: "employee-#{SecureRandom.hex(8)}@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      role: "employee",
      status: "active"
    )
  end

  def create_activity(user:, started_at:, ended_at:, status:)
    Activity.create!(
      user: user,
      activity_type: "walking",
      source: "health_connect",
      started_at: started_at,
      ended_at: ended_at,
      duration_seconds: (ended_at - started_at).to_i,
      status: status
    )
  end
end
