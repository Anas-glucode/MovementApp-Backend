class ImproveAnnouncementCommentIndex < ActiveRecord::Migration[8.1]
  def change
    remove_index :announcement_comments,
                 name: "index_announcement_comments_on_announcement_id_and_created_at"
    add_index :announcement_comments, [ :announcement_id, :created_at, :id ],
              name: "index_announcement_comments_on_announcement_created_id"
  end
end
