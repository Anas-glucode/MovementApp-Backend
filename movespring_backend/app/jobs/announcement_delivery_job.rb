class AnnouncementDeliveryJob < ApplicationJob
  queue_as :default
  BATCH_SIZE = ExpoPushService::BATCH_SIZE
  MAX_ATTEMPTS = 5

  def perform(announcement_id)
    announcement = prepare_deliveries(announcement_id)
    return unless announcement

    mark_abandoned_claims(announcement)
    while (deliveries = claim_batch(announcement.id)).any?
      process_batch(announcement, deliveries)
      return if retry_scheduled?
    end

    finish_delivery(announcement)
  end

  private

  def prepare_deliveries(id)
    Announcement.transaction do
      announcement = Announcement.lock.find_by(id: id)
      return unless announcement&.visible_at?
      return announcement if announcement.delivery_prepared_at.present?

      recipients = PushToken.joins(:user)
                            .where(users: {
                              company_id: announcement.company_id,
                              status: "active"
                            })
                            .order("push_tokens.id")
                            .pluck(:id, :user_id)
      now = Time.current
      AnnouncementDelivery.insert_all(
        recipients.map do |push_token_id, user_id|
          {
            announcement_id: announcement.id,
            push_token_id: push_token_id,
            user_id: user_id,
            status: "pending",
            attempt_count: 0,
            created_at: now,
            updated_at: now
          }
        end,
        unique_by: :index_announcement_deliveries_on_announcement_and_token
      ) if recipients.any?

      announcement.update!(delivery_prepared_at: now)
      announcement
    end
  end

  def claim_batch(announcement_id)
    AnnouncementDelivery.transaction do
      deliveries = AnnouncementDelivery
                   .where(announcement_id: announcement_id, status: "pending")
                   .order(:id)
                   .lock("FOR UPDATE SKIP LOCKED")
                   .limit(BATCH_SIZE)
                   .to_a
      return [] if deliveries.empty?

      now = Time.current
      AnnouncementDelivery.where(id: deliveries.map(&:id)).update_all(
        status: "processing",
        claimed_at: now,
        attempt_count: Arel.sql("attempt_count + 1"),
        updated_at: now
      )
      AnnouncementDelivery.where(id: deliveries.map(&:id)).order(:id).to_a
    end
  end

  def process_batch(announcement, deliveries)
    tokens = deliveries.map do |delivery|
      push_token = delivery.push_token
      next unless push_token&.user_id == delivery.user_id
      next unless delivery.user.active? && delivery.user.company_id == announcement.company_id

      push_token.token
    end
    outcomes = ExpoPushService.call(announcement: announcement, tokens: tokens)
    retry_needed = false

    deliveries.zip(outcomes).each do |delivery, outcome|
      case outcome.fetch(:status)
      when :delivered
        delivery.update!(status: "delivered", delivered_at: Time.current, last_error: nil)
      when :invalid_token
        delivery.push_token&.destroy!
        delivery.update!(status: "failed", last_error: "DeviceNotRegistered")
      when :retry
        retry_needed = true
        retry_or_fail(delivery, outcome[:error])
      when :permanent
        delivery.update!(status: "failed", last_error: outcome[:error])
      else
        delivery.update!(status: "failed", last_error: outcome[:error])
      end
    end

    schedule_retry(announcement, deliveries) if retry_needed &&
      AnnouncementDelivery.where(announcement: announcement, status: "pending").exists?
  rescue ExpoPushService::RetryableError => error
    deliveries.each { |delivery| retry_or_fail(delivery, error.message) }
    schedule_retry(announcement, deliveries)
  rescue ExpoPushService::PermanentError => error
    deliveries.each do |delivery|
      delivery.update!(status: "failed", last_error: error.message)
    end
    Rails.logger.error(
      "Permanent Expo push failure (announcement_id=#{announcement.id}): #{error.message}"
    )
  rescue ExpoPushService::UncertainDeliveryError => error
    deliveries.each do |delivery|
      delivery.update!(status: "unknown", last_error: error.message)
    end
    Rails.logger.error(
      "Unknown Expo push outcome (announcement_id=#{announcement.id}): #{error.message}"
    )
  rescue StandardError => error
    deliveries.each do |delivery|
      delivery.update!(status: "failed", last_error: error.class.name)
    end
    raise
  end

  def retry_or_fail(delivery, error)
    status = delivery.attempt_count >= MAX_ATTEMPTS ? "failed" : "pending"
    delivery.update!(status: status, claimed_at: nil, last_error: error)
    return unless status == "failed"

    Rails.logger.error(
      "Announcement push delivery exhausted retries " \
      "(announcement_id=#{delivery.announcement_id}, delivery_id=#{delivery.id})"
    )
  end

  def mark_abandoned_claims(announcement)
    announcement.announcement_deliveries
                .where(status: "processing")
                .where("claimed_at < ?", 10.minutes.ago)
                .update_all(
                  status: "unknown",
                  last_error: "Worker stopped before saving the provider result",
                  claimed_at: nil,
                  updated_at: Time.current
                )
  end

  def schedule_retry(announcement, deliveries)
    attempts = deliveries.map(&:attempt_count).max || 1
    delay = [ 30.seconds * (2**(attempts - 1)), 1.hour ].min
    self.class.set(wait: delay).perform_later(announcement.id)
    @retry_scheduled = true
  end

  def retry_scheduled?
    value = @retry_scheduled
    @retry_scheduled = false
    value
  end

  def finish_delivery(announcement)
    unfinished = announcement.announcement_deliveries.where(status: %w[pending processing]).exists?
    return if unfinished

    announcement.update_column(:notifications_sent_at, Time.current)
  end
end
