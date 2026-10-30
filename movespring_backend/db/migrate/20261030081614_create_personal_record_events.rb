class CreatePersonalRecordEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :personal_record_events do |t|
      t.references :user, null: false, foreign_key: true

      t.references :activity,
                   null: true,
                   foreign_key: { on_delete: :nullify }

      t.string :record_type, null: false

      t.decimal :previous_value, precision: 15, scale: 2
      t.decimal :new_value, precision: 15, scale: 2, null: false

      t.datetime :achieved_at, null: false
      t.datetime :read_at

      t.timestamps
    end

    add_index :personal_record_events,
              [:user_id, :achieved_at]

    add_index :personal_record_events,
              [:user_id, :record_type, :activity_id],
              unique: true,
              where: "activity_id IS NOT NULL",
              name: "index_personal_record_events_uniquely_per_activity"

    add_check_constraint :personal_record_events,
                         "new_value >= 0",
                         name: "personal_record_events_nonnegative_new_value"

    add_check_constraint :personal_record_events,
                         "previous_value IS NULL OR previous_value >= 0",
                         name: "personal_record_events_nonnegative_previous_value"

    add_check_constraint :personal_record_events,
                         "previous_value IS NULL OR new_value > previous_value",
                         name: "personal_record_events_must_improve_record"
  end
end
