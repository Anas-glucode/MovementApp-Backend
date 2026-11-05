class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :notifications do |t|
      t.references :user, null: false, foreign_key: true

      t.string :notification_type, null: false
      t.string :title, null: false
      t.text :message, null: false

      t.jsonb :data, null: false, default: {}

      t.string :notifiable_type
      t.bigint :notifiable_id

      t.datetime :read_at

      t.timestamps
    end

    # Retrieve a user's notifications in chronological order.
    add_index :notifications, [:user_id, :created_at]

    # Quickly find unread notifications belonging to a user.
    add_index :notifications, [:user_id, :read_at]

    # Find notifications associated with an activity, badge, etc.
    add_index :notifications, [:notifiable_type, :notifiable_id]
  end
end