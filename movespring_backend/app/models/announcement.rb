class Announcement < ApplicationRecord
  belongs_to :company
  belongs_to :created_by, class_name: "User", foreign_key: :created_by_id

  has_many :announcement_reads, dependent: :destroy

  enum :status, {
    draft: "draft",
    published: "published",
    archived: "archived"
  }

  validates :title, presence: true
  validates :body, presence: true
  validates :status, presence: true

  scope :newest_first, -> {
    order(created_at: :desc, id: :desc)
  }

  scope :visible_to_employees, -> {
    published.where("published_at <= ?", Time.current)
  }

  def visible_to_employees?
  published? && published_at.present? && published_at <= Time.current
end
end
