class AnnouncementComment < ApplicationRecord
  belongs_to :announcement
  belongs_to :user
  belongs_to :parent, class_name: "AnnouncementComment", optional: true
  has_many :replies, class_name: "AnnouncementComment",
                     foreign_key: :parent_id,
                     dependent: :destroy,
                     inverse_of: :parent

  validates :body, presence: true, length: { maximum: 2_000 }
  validate :user_belongs_to_announcement_company
  validate :parent_belongs_to_announcement
  validate :parent_must_be_top_level
  after_create_commit :broadcast_created
  after_update_commit :broadcast_updated
  after_destroy_commit :broadcast_deleted

  def as_json
    {
      id: id,
      announcement_id: announcement_id,
      user_id: user_id,
      user_name: user.name,
      parent_id: parent_id,
      body: body,
      created_at: created_at,
      updated_at: updated_at
    }
  end

  private

  def broadcast_created
    broadcast_comment("announcement_comment_created")
  end

  def broadcast_updated
    broadcast_comment("announcement_comment_updated")
  end

  def broadcast_deleted
    ActionCable.server.broadcast(
      "announcements_company_#{announcement.company_id}",
      {
        type: "announcement_comment_deleted",
        comment_id: id,
        announcement_id: announcement_id
      }
    )
  end

  def broadcast_comment(type)
    ActionCable.server.broadcast(
      "announcements_company_#{announcement.company_id}",
      {
        type: type,
        announcement_id: announcement_id,
        comment: as_json
      }
    )
  end

  def parent_belongs_to_announcement
    return if parent.nil? || parent.announcement_id == announcement_id

    errors.add(:parent, "must belong to this announcement")
  end

  def user_belongs_to_announcement_company
    return if user.nil? || announcement.nil?
    return if user.company_id == announcement.company_id

    errors.add(:user, "must belong to the announcement's company")
  end

  def parent_must_be_top_level
    return if parent.nil? || parent.parent_id.nil?

    errors.add(:parent, "cannot be a reply")
  end
end
