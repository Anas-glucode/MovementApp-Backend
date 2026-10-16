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

    if @source == "manual"
      # Nothing measured a manual entry, so a heart rate typed in by the user
      # is only a claim. Drop it.
      @attributes.delete(:average_heart_rate)

      # The server decides how effort was determined, never the client.
      # An effort score means "self reported"; no score means no source at all.
      @attributes[:intensity_source] =
        @attributes[:reported_intensity].present? ? "self_reported" : nil
    end

    activity = @user.activities.new(@attributes)
    activity.source = @source

    if @source == "manual"
      # Only odd-looking manual entries (too long, too old, or starting in the
      # future) wait for an admin. Normal ones are trusted and scored straight away.
      # Ask for a reason to hold this activity. nil means "looks fine".
      review_reason = manual_review_reason(activity)

      if review_reason
        activity.status = "under_review"
        activity.review_reason = review_reason
      else
        activity.status = "eligible"
        activity.validated_at = Time.current
      end
    else
      # Imported workouts still start as "pending" until they are checked.
      activity.status = "pending"
    end

    result = nil

    Activity.transaction do
      if activity.save
        if activity.status == "eligible"
          scoring_rule_version = ScoringRuleVersion
            .where(status: "published")
            .where.not(published_at: nil)
            .order(version_number: :desc)
            .first

          unless scoring_rule_version
            raise ActivityScoringService::ScoringError,
                  "No published scoring rules are available"
          end

          ActivityScoringService.call(
            activity: activity,
            scoring_rule_version: scoring_rule_version
          )
        end


ChallengeActivityScoringService.call_for_activity(activity: activity)

        result = { activity: activity }
      else
        result = { errors: activity.errors.full_messages }
      end
    end

    result
  rescue ActiveRecord::RecordNotUnique
    { errors: ["This activity has already been imported"] }
  rescue ActivityScoringService::ScoringError,
         ChallengeActivityScoringService::ScoringError => e
    { errors: [e.message] }
  rescue ArgumentError, TypeError
    { errors: ["Invalid activity data"] }
  end

  private

  def parse_time(value)
    return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)

    Time.zone.parse(value.to_s)
  end

  # Returns a short reason an admin should look at this entry, or nil if it
  # looks normal. Overlap is checked first because it is the clearest sign of
  # double-counting.
  def manual_review_reason(activity)
    if overlapping_activity_exists?(activity)
      "Overlaps another activity"
    elsif manual_activity_suspicious?(activity)
      "Manual activity requires review"
    end
  end

  # Does this person already have something logged during this time window?
  # Two windows overlap when EACH one starts before the OTHER one ends, so
  # back-to-back activities (end == next start) do not count as overlapping.
  # Rejected activities are ignored, since they earn no points anyway.
  def overlapping_activity_exists?(activity)
    @user.activities
         .where.not(status: "rejected")
         .where("started_at < ? AND ended_at > ?",
                activity.ended_at, activity.started_at)
         .exists?
  end

  # The "this looks odd" rules: too long, too old, starting in the future,
  # or ending in the future (which would earn points for time not yet spent).
  def manual_activity_suspicious?(activity)
    activity.duration_seconds > MAX_MANUAL_DURATION_SECONDS ||
      activity.started_at > MAX_FUTURE_START_MINUTES.minutes.from_now ||
      activity.ended_at > MAX_FUTURE_START_MINUTES.minutes.from_now ||
      activity.started_at < MAX_MANUAL_AGE_DAYS.days.ago
  end
end
