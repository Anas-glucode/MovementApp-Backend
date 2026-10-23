require "test_helper"

class ActivityStreaksTest < ActiveSupport::TestCase
  setup do
    @company = companies(:one)
    @user = User.create!(
      company: @company,
      name: "Streak Tester",
      email: "streak-tester@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      role: "employee",
      status: "active"
    )
  end

  test "sums eligible activity duration per company-local day and enforces threshold" do
    @company.update!(time_zone: "Africa/Johannesburg")

    travel_to Time.utc(2026, 10, 22, 12) do
      create_activity(started_at: Time.utc(2026, 10, 21, 22, 30), duration: 300)
      create_activity(started_at: Time.utc(2026, 10, 21, 22, 45), duration: 300)
      create_activity(started_at: Time.utc(2026, 10, 20, 23), duration: 599)
      create_activity(
        started_at: Time.utc(2026, 10, 21, 23, 15),
        duration: 10.minutes,
        status: "pending"
      )

      result = ActivityStreaks.call(user: @user)

      assert_equal 1, result[:active_days]
      assert_equal 1, result[:longest_daily]
    end
  end

  test "reports longest consecutive daily and weekly runs" do
    travel_to Time.utc(2026, 10, 22, 12) do
      today = Time.current.to_date
      [today - 14.days, today - 7.days, today - 3.days, today - 2.days, today - 1.day].each do |date|
        create_active_day(date)
      end

      result = ActivityStreaks.call(user: @user)

      assert_equal 3, result[:longest_weekly]
      assert_equal 3, result[:longest_daily]
      assert_equal 3, result[:current_daily]
      assert_equal 5, result[:active_days]
    end
  end

  test "yesterday can keep the current streak alive but a full missed day ends it" do
    travel_to Time.utc(2026, 10, 22, 12) do
      today = Time.current.to_date
      create_active_day(today - 2.days)
      create_active_day(today - 1.day)

      assert_equal 2, ActivityStreaks.call(user: @user)[:current_daily]

      @user.activities.destroy_all
      create_active_day(today - 3.days)
      create_active_day(today - 2.days)

      assert_equal 0, ActivityStreaks.call(user: @user)[:current_daily]
    end
  end

  test "unrecognised company time zone falls back to UTC" do
    @company.update_columns(time_zone: "Not/AZone")

    travel_to Time.utc(2026, 10, 22, 12) do
      create_activity(started_at: Time.utc(2026, 10, 21, 23, 55), duration: 10.minutes)

      result = ActivityStreaks.call(user: @user)

      assert_equal 1, result[:active_days]
      assert_equal 1, result[:current_daily]
    end
  end

  private

  def create_active_day(date)
    create_activity(started_at: Time.zone.local(date.year, date.month, date.day, 12), duration: 10.minutes)
  end

  def create_activity(started_at:, duration:, status: "eligible")
    duration_seconds = duration.to_i

    @user.activities.create!(
      activity_type: "walking",
      source: "manual",
      status: status,
      started_at: started_at,
      ended_at: started_at + duration_seconds,
      duration_seconds: duration_seconds
    )
  end
end
