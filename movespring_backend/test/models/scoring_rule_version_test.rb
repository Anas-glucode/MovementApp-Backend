require "test_helper"

class ScoringRuleVersionTest < ActiveSupport::TestCase
  test "allows a valid draft scoring version" do
    version = ScoringRuleVersion.new(
      name: "Draft Rules",
      version_number: 99,
      status: "draft",
      rules: { "sport_rates" => { "walking" => 1.0 } }
    )

    assert version.valid?, version.errors.full_messages.inspect
  end

  test "rejects a published version without a publication timestamp" do
    version = ScoringRuleVersion.new(
      name: "Invalid Published Rules",
      version_number: 99,
      status: "published",
      rules: {}
    )

    assert_not version.valid?
    assert_includes version.errors[:published_at],
                    "must be set for a published scoring version"
  end

  test "rejects publishing rules with a missing or non-positive sport rate" do
    invalid_rules = scoring_rule_versions(:one).rules.deep_dup
    invalid_rules["sport_rates"].delete("golf")
    invalid_rules["sport_rates"]["walking"] = -1.0

    version = ScoringRuleVersion.new(
      name: "Invalid Sport Rates",
      version_number: 99,
      status: "published",
      published_at: Time.current,
      rules: invalid_rules
    )

    assert_not version.valid?
    assert_includes version.errors[:rules],
                    "must include a positive sport rate for every supported activity type"
  end

  test "rejects publishing rules with invalid multipliers or intensity bands" do
    invalid_rules = scoring_rule_versions(:one).rules.deep_dup
    invalid_rules["intensity_multipliers"]["high"] = 0
    invalid_rules["intensity_bands"]["moderate_max"] = 1

    version = ScoringRuleVersion.new(
      name: "Invalid Intensity Rules",
      version_number: 99,
      status: "published",
      published_at: Time.current,
      rules: invalid_rules
    )

    assert_not version.valid?
    assert_includes version.errors[:rules],
                    "must include positive baseline, low, moderate, and high intensity multipliers"
    assert_includes version.errors[:rules],
                    "intensity_bands needs whole numbers: 1 <= low_max < moderate_max < 10"
  end

  test "requires complete rules and a publication timestamp for retired versions" do
    version = ScoringRuleVersion.new(
      name: "Incomplete Retired Rules",
      version_number: 99,
      status: "retired",
      rules: {}
    )

    assert_not version.valid?
    assert_includes version.errors[:published_at],
                    "must be set for a published scoring version"
    assert_includes version.errors[:rules],
                    "must include a positive sport rate for every supported activity type"
    assert_includes version.errors[:rules],
                    "must include positive baseline, low, moderate, and high intensity multipliers"
    assert_includes version.errors[:rules], "intensity_bands must be an object"
  end

  test "rejects zero-valued sport rates" do
    rules = scoring_rule_versions(:one).rules.deep_dup
    rules["sport_rates"]["walking"] = 0
    version = ScoringRuleVersion.new(
      name: "Zero-Rate Rules",
      version_number: 99,
      status: "published",
      published_at: Time.current,
      rules: rules
    )

    assert_not version.valid?
    assert_includes version.errors[:rules],
                    "must include a positive sport rate for every supported activity type"
  end

  test "rejects negative intensity multipliers" do
    rules = scoring_rule_versions(:one).rules.deep_dup
    rules["intensity_multipliers"]["baseline"] = -0.1
    version = ScoringRuleVersion.new(
      name: "Negative Multiplier Rules",
      version_number: 99,
      status: "published",
      published_at: Time.current,
      rules: rules
    )

    assert_not version.valid?
    assert_includes version.errors[:rules],
                    "must include positive baseline, low, moderate, and high intensity multipliers"
  end

  test "allows a zero manual multiplier" do
    rules = scoring_rule_versions(:one).rules.deep_dup
    rules["manual_multiplier"] = 0
    version = ScoringRuleVersion.new(
      name: "Zero Manual Multiplier Rules",
      version_number: 99,
      status: "published",
      published_at: Time.current,
      rules: rules
    )

    assert version.valid?, version.errors.full_messages.inspect
  end

  test "rejects invalid optional scoring settings" do
    rules = scoring_rule_versions(:one).rules.deep_dup
    rules["daily_point_cap"] = 0
    rules["manual_multiplier"] = 1.1
    version = ScoringRuleVersion.new(
      name: "Invalid Optional Settings",
      version_number: 99,
      status: "published",
      published_at: Time.current,
      rules: rules
    )

    assert_not version.valid?
    assert_includes version.errors[:rules],
                    "daily_point_cap must be a whole number > 0"
    assert_includes version.errors[:rules],
                    "manual_multiplier must be between 0 and 1"
  end

  test "prevents editing rules after publication" do
    version = scoring_rule_versions(:one)
    original_rules = version.rules.deep_dup

    version.rules = original_rules.merge(
      "sport_rates" => { "walking" => 999.0 }
    )

    assert_not version.save
    assert_includes version.errors[:rules],
                    "cannot be changed after publishing; create a new version instead"
  end

  test "allows retiring a published version without changing its rules" do
    version = scoring_rule_versions(:one)

    version.status = "retired"

    assert version.save, version.errors.full_messages.inspect
    assert_equal "retired", version.reload.status
  end

  test "prevents editing rules after retirement" do
    version = scoring_rule_versions(:one)
    version.update!(status: "retired")

    version.rules = version.rules.deep_dup.merge(
      "sport_rates" => { "walking" => 999.0 }
    )

    assert_not version.save
    assert_includes version.errors[:base],
                    "Retired scoring rules cannot be edited"
  end

  test "prevents reactivating a retired version" do
    version = scoring_rule_versions(:one)
    version.update!(status: "retired")

    version.status = "published"

    assert_not version.save
    assert_includes version.errors[:status],
                    "cannot be changed once retired"
  end

  test "prevents deleting a published version" do
    version = scoring_rule_versions(:one)

    assert_not version.destroy
    assert_includes version.errors[:base],
                    "Published or retired scoring versions cannot be deleted"
  end

  test "prevents deleting a retired version" do
    version = scoring_rule_versions(:one)
    version.update!(status: "retired")

    assert_not version.destroy
    assert_includes version.errors[:base],
                    "Published or retired scoring versions cannot be deleted"
  end
end
