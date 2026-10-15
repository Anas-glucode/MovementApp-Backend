require "test_helper"

class ChallengeTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(
      name: "Challenge Test Company",
      slug: "challenge-test-#{SecureRandom.hex(4)}",
      status: "active"
    )

    @scoring_rule_version = ScoringRuleVersion.create!(
      name: "Challenge Test Rules",
      version_number: next_scoring_version_number,
      status: "published",
      published_at: Time.current,
      rules: {
        "sport_rates" => {
          "walking" => 1.0
        },
        "intensity_multipliers" => {
          "baseline" => 1.0,
          "low" => 0.8,
          "moderate" => 1.0,
          "high" => 1.2
        },
        "intensity_bands" => {
          "low_max" => 3,
          "moderate_max" => 6
        }
      }
    )

    @challenge = Challenge.new(
      company: @company,
      scoring_rule_version: @scoring_rule_version,
      name: "October Step Challenge",
      description: "Walk more this month",
      starts_at: 1.day.from_now,
      ends_at: 8.days.from_now
    )
  end

  test "valid challenge is valid and defaults to draft" do
    assert_equal "draft", @challenge.status
    assert @challenge.valid?
  end

  test "name is required" do
    @challenge.name = nil

    assert_not @challenge.valid?
    assert_includes @challenge.errors[:name], "can't be blank"
  end

  test "name cannot exceed 150 characters" do
    @challenge.name = "a" * 151

    assert_not @challenge.valid?
    assert_includes @challenge.errors[:name], "is too long (maximum is 150 characters)"
  end

  test "start and end times are required" do
    @challenge.starts_at = nil
    @challenge.ends_at = nil

    assert_not @challenge.valid?
    assert_includes @challenge.errors[:starts_at], "can't be blank"
    assert_includes @challenge.errors[:ends_at], "can't be blank"
  end

  test "end time must be after start time" do
    @challenge.ends_at = @challenge.starts_at

    assert_not @challenge.valid?
    assert_includes @challenge.errors[:ends_at],
                    "must be after the challenge start time"
  end

  test "status must be supported" do
    @challenge.status = "something_else"

    assert_not @challenge.valid?
    assert_includes @challenge.errors[:status], "is not included in the list"
  end

  test "challenge belongs to a company and scoring rule version" do
    assert_equal @company, @challenge.company
    assert_equal @scoring_rule_version, @challenge.scoring_rule_version
  end

  test "published scoring rule version cannot be deleted while referenced by a challenge" do
    @challenge.save!

    assert_no_difference "ScoringRuleVersion.count" do
      @scoring_rule_version.destroy
    end

    assert @scoring_rule_version.persisted?
  end

  private

  def next_scoring_version_number
    (ScoringRuleVersion.maximum(:version_number) || 0) + 1
  end
end
