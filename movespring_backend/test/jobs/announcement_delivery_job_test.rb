require "test_helper"

class AnnouncementDeliveryJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "visible announcement deliveries are persisted independently of broadcasts" do
    announcement = create_announcement
    user = users(:one)
    token = PushToken.create!(user: user, token: "ExponentPushToken[job-test]")
    PushToken.create!(user: users(:two), token: "ExponentPushToken[foreign-company]")
    push_calls = []
    implementation = lambda do |announcement:, tokens:|
      push_calls << [ announcement.id, tokens ]
      tokens.map { { status: :delivered } }
    end
    broadcast_count = AnnouncementBroadcast.count
    with_push_service(implementation) do
      AnnouncementDeliveryJob.perform_now(announcement.id)
    end

    assert_equal broadcast_count, AnnouncementBroadcast.count
    delivery = AnnouncementDelivery.find_by!(announcement: announcement, push_token: token)
    assert_equal "delivered", delivery.status
    assert_equal 1, announcement.announcement_deliveries.count
    assert_equal [ [ announcement.id, [ token.token ] ] ], push_calls
    assert_not_nil announcement.reload.notifications_sent_at
  end

  test "re-running a completed job does not resend a delivered device" do
    announcement = create_announcement
    token = PushToken.create!(user: users(:one), token: "ExponentPushToken[already-sent]")
    call_count = 0

    implementation = lambda do |tokens:, **|
      call_count += 1
      tokens.map { { status: :delivered } }
    end
    with_push_service(implementation) do
      AnnouncementDeliveryJob.perform_now(announcement.id)
      AnnouncementDeliveryJob.perform_now(announcement.id)
    end

    assert_equal 1, call_count
    assert_equal "delivered",
                 AnnouncementDelivery.find_by!(announcement: announcement, push_token: token).status
  end

  test "a transient batch failure leaves delivery pending and enqueues retry" do
    announcement = create_announcement
    token = PushToken.create!(user: users(:one), token: "ExponentPushToken[retry]")

    implementation = lambda do |**|
      raise ExpoPushService::RetryableError, "service unavailable"
    end
    with_push_service(implementation) do
      assert_enqueued_with(job: AnnouncementDeliveryJob) do
        AnnouncementDeliveryJob.perform_now(announcement.id)
      end
    end

    delivery = AnnouncementDelivery.find_by!(announcement: announcement, push_token: token)
    assert_equal "pending", delivery.status, delivery.attributes.inspect
    assert_equal 1, delivery.attempt_count
    assert_nil announcement.reload.notifications_sent_at
  end

  test "successful devices are not resent when a batch has a retryable ticket" do
    announcement = create_announcement
    delivered_token = PushToken.create!(user: users(:one), token: "ExponentPushToken[first]")
    other_company_employee = companies(:one).users.create!(
      name: "Another delivery recipient",
      email: "another-delivery-recipient@example.com",
      password: "Password123!",
      role: "employee",
      status: "active"
    )
    retry_token = PushToken.create!(
      user: other_company_employee,
      token: "ExponentPushToken[second]"
    )
    calls = []

    implementation = lambda do |tokens:, **|
      calls << tokens
      if calls.length == 1
        [
          { status: :delivered },
          { status: :retry, error: "MessageRateExceeded" }
        ]
      else
        [ { status: :delivered } ]
      end
    end
    with_push_service(implementation) do
      AnnouncementDeliveryJob.perform_now(announcement.id)
      assert_equal "pending",
                   AnnouncementDelivery.find_by!(announcement: announcement,
                                                 push_token: retry_token).status
      AnnouncementDeliveryJob.perform_now(announcement.id)
    end

    assert_equal [ delivered_token.token, retry_token.token ].sort, calls.first.sort
    assert_equal [ retry_token.token ], calls.second,
                 "the retry should send only the still-pending device"
    assert_equal "delivered",
                 AnnouncementDelivery.find_by!(announcement: announcement, push_token: delivered_token).status
    assert_equal "delivered",
                 AnnouncementDelivery.find_by!(announcement: announcement, push_token: retry_token).status
  end

  test "future, inactive and expired announcements are not delivered" do
    future = create_announcement(starts_at: 1.day.from_now)
    inactive = create_announcement(active: false)
    expired = create_announcement(starts_at: 2.days.ago, ends_at: 1.day.ago)

    implementation = ->(**) { raise "Ineligible announcements must not send" }
    with_push_service(implementation) do
      [ future, inactive, expired ].each do |announcement|
        AnnouncementDeliveryJob.perform_now(announcement.id)
        assert_nil announcement.reload.delivery_prepared_at
      end
    end
  end

  test "permanent provider failures are recorded and not retried" do
    announcement = create_announcement
    token = PushToken.create!(user: users(:one), token: "ExponentPushToken[permanent]")
    implementation = lambda do |**|
      raise ExpoPushService::PermanentError, "invalid Expo credentials"
    end

    clear_enqueued_jobs
    with_push_service(implementation) do
      assert_no_enqueued_jobs(only: AnnouncementDeliveryJob) do
        AnnouncementDeliveryJob.perform_now(announcement.id)
      end
    end

    delivery = AnnouncementDelivery.find_by!(announcement: announcement, push_token: token)
    assert_equal "failed", delivery.status
    assert_equal "invalid Expo credentials", delivery.last_error
  end

  test "Expo invalid-token tickets remove the token and persist failure" do
    announcement = create_announcement
    token = PushToken.create!(user: users(:one), token: "ExponentPushToken[invalid]")
    implementation = lambda do |**|
      [ { status: :invalid_token, error: "DeviceNotRegistered" } ]
    end

    with_push_service(implementation) do
      AnnouncementDeliveryJob.perform_now(announcement.id)
    end

    delivery = AnnouncementDelivery.find_by!(announcement: announcement, user: users(:one))
    assert_equal "failed", delivery.status
    assert_equal "DeviceNotRegistered", delivery.last_error
    assert_not PushToken.exists?(token: token.token)
  end

  private

  def create_announcement(attributes = {})
    companies(:one).announcements.create!(
      {
        title: "Company announcement",
        message: "Details for employees",
        starts_at: 1.minute.ago
      }.merge(attributes)
    )
  end

  def with_push_service(implementation)
    original_call = ExpoPushService.method(:call)
    ExpoPushService.define_singleton_method(:call, &implementation)
    yield
  ensure
    ExpoPushService.define_singleton_method(:call, original_call)
  end
end
