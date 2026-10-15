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

  test "prevents editing rules after publication" do
    version = scoring_rule_versions(:one)
    original_rules = version.rules.deep_dup

    version.rules = original_rules.merge(
      "sport_rates" => { "walking" => 999.0 }
    )

    assert_not version.save
    assert_includes version.errors[:base],
                    "Published scoring rules cannot be edited; create a new version instead"
  end

  test "allows retiring a published version without changing its rules" do
    version = scoring_rule_versions(:one)

    version.status = "retired"

    assert version.save, version.errors.full_messages.inspect
    assert_equal "retired", version.reload.status
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
