class Message < ApplicationRecord
  belongs_to :user
  belongs_to :chat_room
  has_many_attached :media

  MAX_MEDIA_PER_MESSAGE = 5
  IMAGE_TYPES = %w[image/jpeg image/png image/webp image/gif].freeze
  VIDEO_TYPES = %w[video/mp4 video/quicktime video/webm].freeze
  MAX_IMAGE_SIZE = 10.megabytes
  MAX_VIDEO_SIZE = 50.megabytes

  before_validation { self.body = body.to_s }

  validates :body, length: { maximum: 1000 }
  validates :body, presence: true, unless: -> { media.attached? }
  validate :media_is_valid

  after_create_commit :broadcast_created
  after_destroy_commit :broadcast_deleted

  def as_chat_json
    {
      id: id,
      user_id: user_id,
      user_name: user.name,
      body: body,
      created_at: created_at,
      media: media.map { |m| media_json(m) }
    }
  end

  private

  def media_json(attachment)
    {
      id: attachment.id,
      kind: attachment.content_type.start_with?("video/") ? "video" : "image",
      url: Rails.application.routes.url_helpers.rails_blob_path(attachment, only_path: true),
      content_type: attachment.content_type,
      filename: attachment.filename.to_s,
      byte_size: attachment.byte_size
    }
  end

  def media_is_valid
    return unless media.attached?

    if media.size > MAX_MEDIA_PER_MESSAGE
      errors.add(:media, "cannot have more than #{MAX_MEDIA_PER_MESSAGE} files")
    end

    media.each do |file|
      type = file.content_type
      if IMAGE_TYPES.include?(type)
        errors.add(:media, "#{file.filename} is larger than 10 MB") if file.byte_size > MAX_IMAGE_SIZE
      elsif VIDEO_TYPES.include?(type)
        errors.add(:media, "#{file.filename} is larger than 50 MB") if file.byte_size > MAX_VIDEO_SIZE
      else
        errors.add(:media, "#{file.filename} is not a supported image or video type")
      end
    end
  end

  def broadcast_created
    ActionCable.server.broadcast("chat_room_#{chat_room_id}", as_chat_json.merge(type: "message_created"))
  end

  def broadcast_deleted
    ActionCable.server.broadcast("chat_room_#{chat_room_id}", { type: "message_deleted", id: id })
  end
end