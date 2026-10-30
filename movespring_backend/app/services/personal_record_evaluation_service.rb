
class PersonalRecordEvaluationService
  RECORDS = {
    "longest_run" => :longest_run_meters,
    "longest_cycling_distance" => :longest_cycling_meters,
    "longest_workout" => :max_duration_seconds,
    "highest_daily_steps" => :max_steps_in_a_day,
    "most_active_minutes" => :max_active_seconds_in_a_day,
    "highest_daily_points" => :max_points_in_a_day,
    "highest_weekly_points" => :max_points_in_a_week,
    "longest_streak" => :longest_streak_days
  }.freeze

  def self.call(activity:)
    new(activity).call
  end

  def initialize(activity)
    @activity = activity
    @user = activity.user
  end

  def call
    return unless @activity.status == "eligible"
    return unless @activity.activity_point_award.present?

    @user.with_lock do
      current_records = PersonalRecords.call(user: @user)

      previous_records = PersonalRecords.call(
        user: @user,
        excluding_activity_id: @activity.id
      )

      RECORDS.each do |record_type, record_key|
        new_value = current_records.fetch(record_key, 0).to_d
        previous_value = previous_records.fetch(record_key, 0).to_d

        next unless new_value > previous_value

        event = PersonalRecordEvent.create_or_find_by!(
          user: @user,
          activity: @activity,
          record_type: record_type
        ) do |record_event|
          record_event.previous_value =
            previous_value.positive? ? previous_value : nil

          record_event.new_value = new_value
          record_event.achieved_at = @activity.started_at || Time.current
        end

        next unless event.previously_new_record?

        NotificationCreationService.call(
          user: @user,
          notification_type: "personal_record",
          title: "New personal record!",
          message: "Congratulations! You've achieved a new personal record: #{record_type.humanize}.",
          data: {
            personal_record_event_id: event.id,
            record_type: record_type,
            new_value: new_value
          },
          notifiable: event
        )
      end
    end
  end
end
