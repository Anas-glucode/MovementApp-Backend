require "test_helper"
require "net/http"

class ExpoPushServiceTest < ActiveSupport::TestCase
  test "builds the Expo payload and maps successful tickets" do
    announcement = create_announcement
    test_case = self

    with_http(response_factory: lambda do |request, requests|
      payload = JSON.parse(request.body)
      requests << payload
      test_case.assert_equal "ExponentPushToken[recipient]", payload.first.fetch("to")
      test_case.assert_equal "Notification test", payload.first.fetch("title")
      test_case.assert_equal "Announcement message", payload.first.fetch("body")
      test_case.assert_equal "default", payload.first.fetch("sound")
      test_case.assert_equal announcement.id, payload.first.dig("data", "announcement_id")
      success_response(data: [ { status: "ok", id: "ticket" } ])
    end) do
      outcomes = ExpoPushService.call(
        announcement: announcement,
        tokens: [ "ExponentPushToken[recipient]" ]
      )
      assert_equal :delivered, outcomes.first.fetch(:status)
    end
  end

  test "does not call Expo when no tokens are registered" do
    announcement = create_announcement
    calls = 0

    with_http(response_factory: ->(*) { calls += 1; raise "unexpected HTTP request" }) do
      assert_empty ExpoPushService.call(announcement: announcement, tokens: [])
    end

    assert_equal 0, calls
  end

  test "splits large token lists into batches of 100" do
    announcement = create_announcement
    batch_sizes = []

    with_http(response_factory: lambda do |request, _requests|
      count = JSON.parse(request.body).length
      batch_sizes << count
      success_response(data: Array.new(count) { { status: "ok" } })
    end) do
      outcomes = ExpoPushService.call(
        announcement: announcement,
        tokens: Array.new(205) { |index| "ExponentPushToken[token-#{index}]" }
      )
      assert_equal 205, outcomes.length
    end

    assert_equal [ 100, 100, 5 ], batch_sizes
  end

  test "retries HTTP 429 and server errors but classifies client errors as permanent" do
    announcement = create_announcement

    with_http(status_class: Net::HTTPTooManyRequests, code: "429") do
      assert_raises(ExpoPushService::RetryableError) do
        ExpoPushService.call(announcement: announcement, tokens: [ "ExponentPushToken[a]" ])
      end
    end

    with_http(status_class: Net::HTTPBadRequest, code: "400") do
      assert_raises(ExpoPushService::PermanentError) do
        ExpoPushService.call(announcement: announcement, tokens: [ "ExponentPushToken[a]" ])
      end
    end
  end

  test "malformed Expo responses fail permanently without leaking provider messages" do
    announcement = create_announcement

    with_http(body: "not json") do
      error = assert_raises(ExpoPushService::PermanentError) do
        ExpoPushService.call(announcement: announcement, tokens: [ "ExponentPushToken[a]" ])
      end
      assert_equal "Expo push service returned invalid JSON", error.message
    end

    with_http(body: JSON.generate(data: { unexpected: "structure" })) do
      assert_raises(ExpoPushService::PermanentError) do
        ExpoPushService.call(announcement: announcement, tokens: [ "ExponentPushToken[a]" ])
      end
    end
  end

  test "ticket failures classify invalid, retryable, and permanent tokens" do
    announcement = create_announcement
    tickets = [
      { status: "error", details: { error: "DeviceNotRegistered" } },
      { status: "error", details: { error: "MessageRateExceeded" } },
      { status: "error", details: { error: "InvalidCredentials" } }
    ]

    with_http(body: JSON.generate(data: tickets)) do
      outcomes = ExpoPushService.call(
        announcement: announcement,
        tokens: [
          "ExponentPushToken[invalid]",
          "ExponentPushToken[retry]",
          "ExponentPushToken[permanent]"
        ]
      )
      assert_equal [ :invalid_token, :retry, :permanent ], outcomes.pluck(:status)
      assert_equal "Expo rejected notification (InvalidCredentials)", outcomes.last.fetch(:error)
    end
  end

  test "network timeouts are marked uncertain rather than blindly retried" do
    announcement = create_announcement
    original_start = Net::HTTP.method(:start)
    Net::HTTP.define_singleton_method(:start) do |*_args, **_options, &|
      raise Net::ReadTimeout
    end

    assert_raises(ExpoPushService::UncertainDeliveryError) do
      ExpoPushService.call(announcement: announcement, tokens: [ "ExponentPushToken[a]" ])
    end
  ensure
    Net::HTTP.define_singleton_method(:start, original_start)
  end

  private

  def create_announcement
    companies(:one).announcements.create!(
      title: "Notification test",
      message: "Announcement message",
      starts_at: 1.minute.ago
    )
  end

  def success_response(data:)
    { status_class: Net::HTTPSuccess, code: "200", body: JSON.generate(data: data) }
  end

  def with_http(response_factory: nil, status_class: Net::HTTPSuccess, code: "200", body: nil)
    http = Object.new
    factory = response_factory || ->(*) { { status_class: status_class, code: code, body: body } }
    http.define_singleton_method(:request) do |request|
      response_data = factory.call(request, [])
      response = Object.new
      response.define_singleton_method(:is_a?) do |klass|
        klass == response_data.fetch(:status_class) || klass == Net::HTTPResponse || super(klass)
      end
      response.define_singleton_method(:code) { response_data.fetch(:code) }
      response.define_singleton_method(:body) { response_data.fetch(:body) || "" }
      response
    end

    original_start = Net::HTTP.method(:start)
    Net::HTTP.define_singleton_method(:start) do |*_args, **_options, &block|
      block.call(http)
    end

    yield
  ensure
    Net::HTTP.define_singleton_method(:start, original_start)
  end
end
