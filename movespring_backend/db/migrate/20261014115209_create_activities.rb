class CreateActivities < ActiveRecord::Migration[8.1]
  def change
    create_table :activities do |t|
      t.references :user, null: false, foreign_key: true

      t.string :activity_type, null: false
      t.string :source, null: false
      t.string :source_record_id

      t.datetime :started_at, null: false
      t.datetime :ended_at, null: false
      t.integer :duration_seconds, null: false

      t.decimal :distance_meters, precision: 12, scale: 2
      t.integer :steps
      t.decimal :active_calories, precision: 10, scale: 2

      t.integer :average_heart_rate
      t.string :intensity_source
      t.integer :reported_intensity

      t.string :status, null: false, default: "pending"
      t.string :review_reason
      t.datetime :validated_at
      t.string :time_zone

      t.timestamps
    end

    add_index :activities,
              [:user_id, :started_at],
              name: "index_activities_on_user_and_started_at"

    add_index :activities,
              [:user_id, :status],
              name: "index_activities_on_user_and_status"

    add_index :activities,
              [:user_id, :source, :source_record_id],
              unique: true,
              where: "source_record_id IS NOT NULL",
              name: "index_activities_on_unique_source_record"

    add_check_constraint :activities,
                         "source IN ('healthkit', 'health_connect', 'manual')",
                         name: "activities_valid_source"

    add_check_constraint :activities,
                         "status IN ('pending', 'eligible', 'under_review', 'rejected')",
                         name: "activities_valid_status"

    add_check_constraint :activities,
                         "duration_seconds > 0",
                         name: "activities_positive_duration"

    add_check_constraint :activities,
                         "ended_at > started_at",
                         name: "activities_valid_time_range"

    add_check_constraint :activities,
                         "steps IS NULL OR steps >= 0",
                         name: "activities_nonnegative_steps"

    add_check_constraint :activities,
                         "distance_meters IS NULL OR distance_meters >= 0",
                         name: "activities_nonnegative_distance"

    add_check_constraint :activities,
                         "active_calories IS NULL OR active_calories >= 0",
                         name: "activities_nonnegative_calories"

    add_check_constraint :activities,
                         "reported_intensity IS NULL OR reported_intensity BETWEEN 1 AND 10",
                         name: "activities_valid_reported_intensity"

    add_check_constraint :activities,
                         "average_heart_rate IS NULL OR average_heart_rate BETWEEN 1 AND 250",
                         name: "activities_valid_heart_rate"
  end
end
