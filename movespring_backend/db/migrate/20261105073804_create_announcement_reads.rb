
class CreateAnnouncementReads < ActiveRecord::Migration[8.1]
  def change
    create_table :announcement_reads do |t|
      t.references :announcement, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.datetime :read_at, null: false

      t.timestamps
    end

    add_index :announcement_reads,
              [:announcement_id, :user_id],
              unique: true,
              name: "index_announcement_reads_on_announcement_and_user"
  end
end
