require "net/smtp"
require "socket"

Rails.application.config.after_initialize do
  ActionMailer::MailDeliveryJob.retry_on(
    Net::OpenTimeout,
    Net::ReadTimeout,
    Errno::ECONNREFUSED,
    Errno::ECONNRESET,
    SocketError,
    Net::SMTPServerBusy,
    wait: :polynomially_longer,
    attempts: 8
  ) do |job, error|
    Rails.logger.error(
      "[mail] gave up on #{job.arguments.first(2).inspect}: " \
      "#{error.class} - #{error.message}"
    )
  end
end
