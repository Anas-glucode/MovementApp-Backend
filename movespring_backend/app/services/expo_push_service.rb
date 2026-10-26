require "json"
require "net/http"
require "openssl"
require "socket"

class ExpoPushService
  ENDPOINT = URI("https://exp.host/--/api/v2/push/send")
  BATCH_SIZE = 100

  class DeliveryError < StandardError; end
  class RetryableError < DeliveryError; end
  class PermanentError < DeliveryError; end
  class UncertainDeliveryError < DeliveryError; end

  def self.call(announcement:, tokens:)
    new(announcement, tokens).call
  end

  def initialize(announcement, tokens)
    @announcement = announcement
    @tokens = tokens
  end

  def call
    return [] if @tokens.empty?

    @tokens.each_slice(BATCH_SIZE).flat_map { |batch| deliver(batch) }
  end

  private

  def deliver(tokens)
    valid_tokens = tokens.each_with_index.filter_map do |token, index|
      [ token, index ] if token.present?
    end
    outcomes = Array.new(tokens.length)
    tokens.each_index do |index|
      outcomes[index] = { status: :permanent, error: "Push token is unavailable" } if tokens[index].blank?
    end
    return outcomes if valid_tokens.empty?

    payload = valid_tokens.map do |token, _index|
      {
        to: token,
        title: @announcement.title,
        body: @announcement.message.truncate(200),
        sound: "default",
        data: { type: "announcement", announcement_id: @announcement.id }
      }
    end

    request = Net::HTTP::Post.new(ENDPOINT)
    request["Content-Type"] = "application/json"
    request["Accept"] = "application/json"
    request["Authorization"] = "Bearer #{ENV.fetch('EXPO_ACCESS_TOKEN')}" if ENV["EXPO_ACCESS_TOKEN"].present?
    request.body = JSON.generate(payload)

    response = Net::HTTP.start(
      ENDPOINT.host,
      ENDPOINT.port,
      use_ssl: true,
      open_timeout: 5,
      read_timeout: 15
    ) { |http| http.request(request) }

    provider_outcomes = classify_http_response(response, valid_tokens.length)
    valid_tokens.zip(provider_outcomes).each do |(_token, index), outcome|
      outcomes[index] = outcome
    end
    outcomes
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, OpenSSL::SSL::SSLError,
         Errno::ECONNRESET, Errno::EPIPE => error
    raise UncertainDeliveryError, "Expo delivery outcome is unknown (#{error.class})"
  end

  def classify_http_response(response, token_count)
    if response.is_a?(Net::HTTPTooManyRequests) || response.is_a?(Net::HTTPServerError)
      raise RetryableError, "Expo push service temporarily unavailable (HTTP #{response.code})"
    end
    unless response.is_a?(Net::HTTPSuccess)
      raise PermanentError, "Expo push service rejected the request (HTTP #{response.code})"
    end

    tickets = JSON.parse(response.body)["data"]
    unless tickets.is_a?(Array) && tickets.length == token_count &&
           tickets.all? { |ticket| ticket.is_a?(Hash) && %w[ok error].include?(ticket["status"]) }
      raise PermanentError, "Expo push service returned an invalid ticket response"
    end

    tickets.map { |ticket| ticket_outcome(ticket) }
  rescue JSON::ParserError
    raise PermanentError, "Expo push service returned invalid JSON"
  end

  def ticket_outcome(ticket)
    return { status: :delivered } if ticket["status"] == "ok"

    details = ticket["details"]
    error = details.is_a?(Hash) ? details["error"].to_s : ""
    case error
    when "DeviceNotRegistered"
      { status: :invalid_token, error: error }
    when "MessageRateExceeded"
      { status: :retry, error: error }
    else
      { status: :permanent, error: "Expo rejected notification (#{safe_error_code(error)})" }
    end
  end

  def safe_error_code(error)
    %w[InvalidCredentials MessageTooBig MessageRateExceeded DeviceNotRegistered].include?(error) ?
      error : "unknown error"
  end
end
