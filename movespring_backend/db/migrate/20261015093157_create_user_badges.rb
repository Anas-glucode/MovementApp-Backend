class CreateUserBadges < ActiveRecord::Migration[8.0]
  def change
    create_table :user_badges do |t|
      t.references :user, null: false, foreign_key: true
      t.references :badge, null: false, foreign_key: true
      t.references :activity, null: true, foreign_key: true
      t.datetime :earned_at, null: false

      t.timestamps
    end

    # Ensure a user can only earn a specific badge once
    add_index :user_badges, [:user_id, :badge_id], unique: true
  end
end