class PushToken < ApplicationRecord
  belongs_to :user

  validates :token, presence: true,
                    format: { with: /\A(?:ExpoPushToken|ExponentPushToken)\[[^\]]+\]\z/ },
                    uniqueness: true
  has_many :announcement_deliveries, dependent: :nullify

  def self.register_for!(user:, token:)
    begin
      transaction do
        existing = lock.find_by(token: token)
        if existing
          existing.update!(user: user)
          existing
        else
          candidate = new(user: user, token: token)
          candidate.valid? ? create!(user: user, token: token) : candidate
        end
      end
    rescue ActiveRecord::RecordNotUnique
      existing = find_by!(token: token)
      existing.with_lock { existing.update!(user: user) }
      existing
    end
  end
end
