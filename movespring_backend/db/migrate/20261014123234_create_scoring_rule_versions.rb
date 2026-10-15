class CreateScoringRuleVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :scoring_rule_versions do |t|
      t.string :name, null: false
      t.integer :version_number, null: false
      t.string :status, null: false, default: "draft"
      t.jsonb :rules, null: false, default: {}
      t.datetime :published_at

      t.timestamps
    end

    add_index :scoring_rule_versions, :version_number, unique: true

    add_check_constraint :scoring_rule_versions,
                         "version_number > 0",
                         name: "scoring_rule_versions_positive_version"

    add_check_constraint :scoring_rule_versions,
                         "status IN ('draft', 'published', 'retired')",
                         name: "scoring_rule_versions_valid_status"

    add_check_constraint :scoring_rule_versions,
                         "jsonb_typeof(rules) = 'object'",
                         name: "scoring_rule_versions_rules_must_be_object"
  end
end
