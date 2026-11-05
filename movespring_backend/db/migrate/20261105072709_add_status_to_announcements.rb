class AddStatusToAnnouncements < ActiveRecord::Migration[8.1]
  def change
    add_column :announcements, :status, :string, null: false, default: "draft"

    add_index :announcements, [:company_id, :status, :published_at]
  end
end
