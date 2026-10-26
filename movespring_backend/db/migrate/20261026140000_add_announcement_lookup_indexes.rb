class AddAnnouncementLookupIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :users, [ :company_id, :status ],
              name: "index_users_on_company_id_and_status"
    add_index :announcement_dismissals, [ :user_id, :announcement_id ],
              name: "index_announcement_dismissals_on_user_and_announcement"
  end
end
