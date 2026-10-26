class CreateAnnouncements < ActiveRecord::Migration[8.1]
  def change
    create_table :announcements do |t|
      t.references :company, null: false, foreign_key: true
      t.string :title, null: false
      t.text :message, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :announcements, [ :company_id, :active, :starts_at ]
    add_check_constraint :announcements,
                         "ends_at IS NULL OR ends_at > starts_at",
                         name: "announcements_valid_dates"

    create_table :announcement_dismissals do |t|
      t.references :announcement, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end

    add_index :announcement_dismissals, [ :announcement_id, :user_id ],
              unique: true, name: "index_announcement_dismissals_on_announcement_and_user"
  end
end
