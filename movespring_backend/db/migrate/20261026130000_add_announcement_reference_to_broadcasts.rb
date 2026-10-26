class AddAnnouncementReferenceToBroadcasts < ActiveRecord::Migration[8.1]
  def change
    add_column :announcement_broadcasts, :announcement_reference_id, :bigint
    add_index :announcement_broadcasts, :announcement_reference_id,
              name: "index_announcement_broadcasts_on_announcement_reference"
  end
end
