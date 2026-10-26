class AddAnnouncementDeliveryAndDiscussion < ActiveRecord::Migration[8.1]
  def change
    add_column :announcements, :notifications_sent_at, :datetime

    create_table :push_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token, null: false

      t.timestamps
    end
    add_index :push_tokens, :token, unique: true

    create_table :announcement_comments do |t|
      t.references :announcement, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :parent, foreign_key: { to_table: :announcement_comments }
      t.text :body, null: false

      t.timestamps
    end
    add_index :announcement_comments, [ :announcement_id, :created_at ]
  end
end
