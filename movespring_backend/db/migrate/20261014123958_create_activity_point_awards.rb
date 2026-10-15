
class CreateActivityPointAwards < ActiveRecord::Migration[8.1]
  def change
    create_table :activity_point_awards do |t|
      t.references :activity, null: false, foreign_key: true, index: false
      t.references :scoring_rule_version, null: false, foreign_key: true
      t.integer :points, null: false

      t.timestamps
    end

    add_index :activity_point_awards, :activity_id, unique: true

    add_check_constraint :activity_point_awards,
                         "points >= 0",
                         name: "activity_point_awards_nonnegative_points"
  end
end
