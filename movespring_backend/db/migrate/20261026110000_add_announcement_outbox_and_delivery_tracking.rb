class AddAnnouncementOutboxAndDeliveryTracking < ActiveRecord::Migration[8.1]
  def change
    add_column :announcements, :delivery_prepared_at, :datetime

    create_table :announcement_deliveries do |t|
      t.references :announcement, null: false, foreign_key: true
      t.references :push_token, foreign_key: { on_delete: :nullify }
      t.references :user, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.integer :attempt_count, null: false, default: 0
      t.datetime :claimed_at
      t.datetime :delivered_at
      t.text :last_error

      t.timestamps
    end
    add_index :announcement_deliveries, [ :announcement_id, :push_token_id ],
              unique: true, name: "index_announcement_deliveries_on_announcement_and_token"
    add_index :announcement_deliveries, [ :announcement_id, :status ],
              name: "index_announcement_deliveries_on_announcement_and_status"
    add_check_constraint :announcement_deliveries,
                         "status IN ('pending', 'processing', 'delivered', 'failed', 'unknown')",
                         name: "announcement_deliveries_valid_status"

    create_table :announcement_broadcasts do |t|
      t.references :announcement, foreign_key: { on_delete: :nullify }
      t.references :company, null: false, foreign_key: true
      t.string :event_key, null: false
      t.string :event_type, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :available_at, null: false
      t.datetime :claimed_at
      t.datetime :broadcasted_at
      t.text :last_error

      t.timestamps
    end
    add_index :announcement_broadcasts, :event_key, unique: true
    add_index :announcement_broadcasts, [ :status, :available_at ],
              name: "index_announcement_broadcasts_on_status_and_available_at"
    add_check_constraint :announcement_broadcasts,
                         "status IN ('pending', 'processing', 'broadcasted', 'discarded')",
                         name: "announcement_broadcasts_valid_status"
  end
end
