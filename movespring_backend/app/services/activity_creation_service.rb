# Creates ONE activity for ONE user and, if it qualifies, scores it straight away.
#
# Think of it as a front desk with three jobs, always in this order:
#   1. CHECK the paperwork   (are the times valid, is it in the future, etc.)
#   2. DECIDE the lane       (looks fine -> scored now, looks odd -> admin review)
#   3. SAVE + SCORE it       (all-or-nothing: if scoring fails, nothing is saved)
#
# Two kinds of activity come through here:
#   * "manual"                   typed in by the person. Only a CLAIM.
#   * "healthkit"/"health_connect" sent by the phone app. Device-reported.
#
# The server decides how much to trust each one. The client never gets to
# say "treat me as trusted".
class ActivityCreationService
  ALLOWED_SOURCES = %w[healthkit health_connect manual].freeze

  # ---- Rules for EVERY activity ----
  MIN_DURATION_SECONDS = 60
  # Phone clocks drift a little, so we tolerate a couple of minutes, but
  # nobody earns points for time that has not happened yet.
  CLOCK_SKEW_TOLERANCE = 2.minutes
  DURATION_TOLERANCE_SECONDS = 60

  # ---- Manual-entry rules ----
  MAX_MANUAL_DURATION_SECONDS = 3 * 60 * 60
  MAX_MANUAL_AGE_DAYS = 30
  MAX_MANUAL_PER_DAY = 5

  # ---- Imported-workout rules ----
  MAX_IMPORT_DURATION_SECONDS = 8 * 60 * 60
  MAX_IMPORT_AGE_DAYS = 30

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

    problem = clean_and_check_inputs
    return { errors: [problem] } if problem

    save_and_score
  rescue ActiveRecord::RecordNotUnique => e
    # Only the "same device record sent twice" index means "already imported".
    # Any other unique-index problem is a real bug, so let it surface.
    raise unless e.message.include?("index_activities_on_unique_source_record")

    { errors: ["This activity has already been imported"], duplicate: true }
  rescue ActivityScoringService::ScoringError,
         ChallengeActivityScoringService::ScoringError => e
    { errors: [e.message] }
  end

  private

  # ------------------------------------------------------------------
  # STEP 1: check the paperwork.
  # Returns an error message (String) if something is wrong, or nil if OK.
  # Also tidies @attributes as it goes.
  # ------------------------------------------------------------------
  def clean_and_check_inputs
    activity_type = @attributes[:activity_type].to_s
    return "Unsupported activity type" unless Activity::TYPES.include?(activity_type)

    @attributes[:activity_type] = activity_type

    started_at = parse_time(@attributes[:started_at])
    ended_at = parse_time(@attributes[:ended_at])

    unless started_at && ended_at
      return "Start and end times are required, as ISO 8601 with a UTC offset " \
             "(for example 2026-10-21T07:30:00+02:00)"
    end

    return "End time must be after the start time" unless ended_at > started_at

    # Since ended_at > started_at, checking the end covers the start too.
    if ended_at > Time.current + CLOCK_SKEW_TOLERANCE
      return "Activity cannot be in the future"
    end

    elapsed_seconds = (ended_at - started_at).round
    if elapsed_seconds < MIN_DURATION_SECONDS
      return "Activity must be at least 1 minute long"
    end

    @attributes[:started_at] = started_at
    @attributes[:ended_at] = ended_at

    if @source == "manual"
      check_manual_inputs(elapsed_seconds)
    else
      check_import_inputs(elapsed_seconds, started_at)
    end
  end

  def check_manual_inputs(elapsed_seconds)
    # For manual entries we work the duration out from the times, so the
    # person can't claim a duration that disagrees with them.
    @attributes[:duration_seconds] = elapsed_seconds

    # No effort score used to mean "baseline" (1.0), which paid MORE than an
    # honest "low effort" (0.8). Making the score compulsory closes that loophole.
    return "Effort level (1-10) is required" if @attributes[:reported_intensity].blank?

    # Nothing measured a manual entry, so a typed-in heart rate is only a claim.
    @attributes.delete(:average_heart_rate)
    # Manual entries never have a device record ID.
    @attributes.delete(:source_record_id)
    # The server decides how effort was determined, never the client.
    @attributes[:intensity_source] = "self_reported"

    nil
  end

  def check_import_inputs(elapsed_seconds, started_at)
    # Without the health platform's own ID for the workout there is nothing to
    # recognise a repeat by, so the same workout could be sent again and again.
    return "A source record ID is required for imported activities" if @attributes[:source_record_id].blank?

    if started_at < MAX_IMPORT_AGE_DAYS.days.ago
      return "Imported activities older than #{MAX_IMPORT_AGE_DAYS} days are not accepted"
    end

    reported_duration = @attributes[:duration_seconds].to_i
    if reported_duration <= 0 ||
       (reported_duration - elapsed_seconds).abs > DURATION_TOLERANCE_SECONDS
      return "Reported duration does not match the activity times"
    end

    @attributes[:duration_seconds] = reported_duration

    # A watch does not hand over a 1-10 "how hard did it feel" score, so a
    # client-supplied one is ignored rather than trusted.
    @attributes.delete(:reported_intensity)
    # The server decides how effort was measured.
    @attributes[:intensity_source] = @attributes[:average_heart_rate].present? ? "heart_rate" : nil

    nil
  end

  # ------------------------------------------------------------------
  # STEPS 2 and 3: decide the lane, then save and score.
  # ------------------------------------------------------------------
  def save_and_score
    result = nil

    Activity.transaction do
      # Lock THIS person's row. Two requests from the same person now queue up
      # one behind the other, like one till serving one customer at a time.
      # Without this, two simultaneous requests could both pass the overlap
      # and daily-limit checks below before either one saved.
      @user.lock!

      activity = @user.activities.new(@attributes)
      activity.source = @source

      result =
        if (message = exact_duplicate_message(activity))
          { errors: [message], duplicate: true }
        elsif (message = manual_limit_message(activity))
          { errors: [message] }
        else
          decide_lane(activity)

          if activity.save
            score(activity)
            { activity: activity }
          else
            { errors: activity.errors.full_messages }
          end
        end
    end

    result
  end

  # Looks fine -> "eligible" and scored straight away.
  # Looks odd   -> "under_review" and waits for an administrator.
  def decide_lane(activity)
    reason =
      if @source == "manual"
        manual_review_reason(activity)
      else
        import_review_reason(activity)
      end

    if reason
      activity.status = "under_review"
      activity.review_reason = reason
    else
      activity.status = "eligible"
      activity.validated_at = Time.current
    end
  end

  def score(activity)
    return unless activity.status == "eligible"

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

    ChallengeActivityScoringService.call_for_activity(activity: activity)
  end

  # ------------------------------------------------------------------
  # The "does this look odd?" rules
  # ------------------------------------------------------------------

  # Exactly the same sport, start and end already logged. This is nearly always
  # a double-tap or the same workout entered twice, so we refuse it politely
  # instead of filling the admin's review queue.
  def exact_duplicate_message(activity)
    duplicate = @user.activities
                     .where.not(status: "rejected")
                     .where(activity_type: activity.activity_type,
                            started_at: activity.started_at,
                            ended_at: activity.ended_at)
                     .exists?

    "This activity has already been logged" if duplicate
  end

  # Caps how many manual entries one person can log per day.
  def manual_limit_message(activity)
    return nil unless @source == "manual"

    count_today = @user.activities
                       .where(source: "manual")
                       .where.not(status: "rejected")
                       .where(started_at: DailyPointCap.day_range(activity))
                       .count

    return nil if count_today < MAX_MANUAL_PER_DAY

    "You can log at most #{MAX_MANUAL_PER_DAY} manual activities per day"
  end

  # Returns a short reason an admin should look at this manual entry, or nil.
  # Overlap is checked first because it is the clearest sign of double-counting.
  def manual_review_reason(activity)
    if overlaps_any_activity?(activity)
      "Overlaps another activity"
    elsif activity.duration_seconds > MAX_MANUAL_DURATION_SECONDS ||
          activity.started_at < MAX_MANUAL_AGE_DAYS.days.ago
      "Manual activity requires review"
    else
      ActivityPlausibilityChecker.call(activity: activity)
    end
  end

  # Same idea for imported workouts, with import-specific rules.
  def import_review_reason(activity)
    if activity.duration_seconds > MAX_IMPORT_DURATION_SECONDS
      "Unusually long workout"
    elsif overlaps_other_source?(activity)
      # e.g. the same run typed in by hand AND imported from the watch
      "Overlaps an activity from another source"
    else
      ActivityPlausibilityChecker.call(activity: activity)
    end
  end

  # Two windows overlap when EACH one starts before the OTHER one ends, so
  # back-to-back activities (end == next start) do not overlap.
  # Rejected activities are ignored, since they earn no points anyway.
  def overlapping_scope(activity)
    @user.activities
         .where.not(status: "rejected")
         .where("started_at < ? AND ended_at > ?",
                activity.ended_at, activity.started_at)
  end

  def overlaps_any_activity?(activity)
    overlapping_scope(activity).exists?
  end

  # Imports from the SAME source (e.g. a daily-steps record next to a run from
  # the same watch) are normal and ignored. We only care when a DIFFERENT source
  # logged the same sport at the same time.
  def overlaps_other_source?(activity)
    overlapping_scope(activity)
      .where.not(source: activity.source)
      .where(activity_type: activity.activity_type)
      .exists?
  end

  # ------------------------------------------------------------------
  # Time parsing
  # ------------------------------------------------------------------
  # Strings MUST end in "Z" or an offset like +02:00. A time with no offset
  # ("2026-10-21T07:30:00") is ambiguous: 07:30 where? We used to guess using
  # the server's time zone. Now we refuse to guess.
  def parse_time(value)
    return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)

    text = value.to_s.strip
    return nil unless text.match?(/(Z|[+-]\d{2}:\d{2})\z/i)

    Time.iso8601(text)
  rescue ArgumentError
    nil
  end
end