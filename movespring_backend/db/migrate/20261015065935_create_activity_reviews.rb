class CreateActivityReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :activity_reviews do |t|
      t.references :activity,
                   null: false,
                   foreign_key: true,
                   index: { unique: true }

      t.references :reviewer,
                   null: false,
                   foreign_key: { to_table: :users }

      t.string :decision, null: false
      t.text :reason
      t.datetime :reviewed_at, null: false

      t.timestamps
    end

    add_check_constraint :activity_reviews,
                         "decision IN ('approved', 'rejected')",
                         name: "activity_reviews_valid_decision"

    add_check_constraint :activity_reviews,
                         "decision != 'rejected' OR length(trim(reason)) > 0",
                         name: "activity_reviews_rejection_requires_reason"
  end
end
