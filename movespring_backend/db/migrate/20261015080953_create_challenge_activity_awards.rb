
class CreateChallengeActivityAwards < ActiveRecord::Migration[8.1]
  def change
    create_table :challenge_activity_awards do |t|
      t.references :challenge, null: false, foreign_key: true
      t.references :activity, null: false, foreign_key: true
      t.references :scoring_rule_version, null: false, foreign_key: true

      t.integer :points, null: false

      t.timestamps
    end

    add_index :challenge_activity_awards,
              [:challenge_id, :activity_id],
              unique: true,
              name: "index_challenge_activity_awards_on_challenge_and_activity"

    add_check_constraint :challenge_activity_awards,
                         "points >= 0",
                         name: "challenge_activity_awards_nonnegative_points"
  end
end
