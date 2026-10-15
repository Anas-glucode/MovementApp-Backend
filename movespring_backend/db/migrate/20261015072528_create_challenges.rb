class CreateChallenges < ActiveRecord::Migration[8.1]
  def change
    create_table :challenges do |t|
      t.references :company, null: false, foreign_key: true
      t.references :scoring_rule_version, null: false, foreign_key: true

      t.string :name, null: false
      t.text :description
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.string :status, null: false, default: "draft"

      t.timestamps
    end

    add_check_constraint :challenges,
                         "status IN ('draft', 'published', 'active', 'completed', 'cancelled')",
                         name: "challenges_valid_status"

    add_check_constraint :challenges,
                         "ends_at > starts_at",
                         name: "challenges_valid_dates"

    add_index :challenges, [:company_id, :status]
    add_index :challenges, [:company_id, :starts_at]
  end
end
