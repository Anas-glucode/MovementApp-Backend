class ActivityCreationService
  SUPPORTED_ACTIVITY_TYPES = %w[
    walking
    running
    cycling
    swimming
    football
    strength_training
    golf
  ].freeze

  ALLOWED_SOURCES = %w[
    healthkit
    health_connect
    manual
  ].freeze

  MAX_MANUAL_DURATION_SECONDS = 3 * 60 * 60
  MAX_FUTURE_START_MINUTES = 5
  MAX_MANUAL_AGE_DAYS = 30
  DURATION_TOLERANCE_SECONDS = 60

  PERMITTED_ATTRIBUTES = %i[
    activity_type
    source_record_id
    started_at
    ended_at
    duration_seconds
    distance_meters
    steps
    active_calories
    average_heart_rate
    intensity_source
    reported_intensity
    time_zone
  ].freeze

  def self.call(user:, attributes:, source:)
    new(user: user, attributes: attributes, source: source).call
  end

  def initialize(user:, attributes:, source:)
    @user = user
    @attributes = attributes.to_h.symbolize_keys.slice(*PERMITTED_ATTRIBUTES)
    @source = source.to_s
  end

  def call
    return { errors: ["User is required"] } unless @user
    return { errors: ["Unsupported activity source"] } unless ALLOWED_SOURCES.include?(@source)

    activity_type = @attributes[:activity_type].to_s
    unless SUPPORTED_ACTIVITY_TYPES.include?(activity_type)
      return { errors: ["Unsupported activity type"] }
    end

    @attributes[:activity_type] = activity_type

    unless @attributes[:started_at].present? && @attributes[:ended_at].present?
      return { errors: ["Start and end times are required"] }
    end

    started_at = parse_time(@attributes[:started_at])
    ended_at = parse_time(@attributes[:ended_at])

    unless started_at && ended_at && ended_at > started_at
      return { errors: ["A valid start and end time are required"] }
    end

    @attributes[:started_at] = started_at
    @attributes[:ended_at] = ended_at

    elapsed_seconds = (ended_at - started_at).round

    if @source == "manual"
      @attributes[:duration_seconds] = elapsed_seconds
    else
      reported_duration = @attributes[:duration_seconds].to_i

      if reported_duration <= 0 ||
         (reported_duration - elapsed_seconds).abs > DURATION_TOLERANCE_SECONDS
        return { errors: ["Reported duration does not match the activity times"] }
      end

      @attributes[:duration_seconds] = reported_duration
    end

    activity = @user.activities.new(@attributes)
    activity.source = @source

    if @source == "manual"
      if manual_activity_suspicious?(activity)
        activity.status = "under_review"
        activity.review_reason = "Manual activity requires review"
      else
        activity.status = "eligible"
        activity.validated_at = Time.current
      end
    else
      activity.status = "pending"
    end

    if activity.save
      { activity: activity }
    else
      { errors: activity.errors.full_messages }
    end
  rescue ActiveRecord::RecordNotUnique
    { errors: ["This activity has already been imported"] }
  rescue ArgumentError, TypeError
    { errors: ["Invalid activity data"] }
  end

  private

  def parse_time(value)
    return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)

    Time.zone.parse(value.to_s)
  end

  def manual_activity_suspicious?(activity)
    activity.duration_seconds > MAX_MANUAL_DURATION_SECONDS ||
      activity.started_at > MAX_FUTURE_START_MINUTES.minutes.from_now ||
      activity.started_at < MAX_MANUAL_AGE_DAYS.days.ago
  end
end
