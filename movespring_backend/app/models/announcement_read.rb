
class AnnouncementRead < ApplicationRecord
  belongs_to :announcement
  belongs_to :user

  validates :read_at, presence: true
  validates :user_id, uniqueness: {
    scope: :announcement_id,
    message: "has already read this announcement"
  }

  validate :user_belongs_to_announcement_company

  private

  def user_belongs_to_announcement_company
    return unless announcement && user

    unless user.company_id == announcement.company_id
      errors.add(:user, "must belong to the announcement's company")
    end
  end
end
