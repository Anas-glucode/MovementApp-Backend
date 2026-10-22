# Moves challenges through their life on a timer, like a stage manager
# calling the cues:
#
#   published  -> active      when the start time passes
#   active     -> finalizing  when the end time passes
#   finalizing -> completed   when the grace period is over AND no activity
#                             from the challenge is still waiting for review
#
# It is safe to run as often as you like (every few minutes). Running it
# twice does nothing the second time. If the scheduler was down for a day, one
# run catches up, because each step looks at the clock again.
class ChallengeLifecycleService
  # How long after the end late syncs and reviews are given before results
  # can be locked automatically. Admins can also finalise earlier by hand.
  FINALIZATION_GRACE = 48.hours

  def self.call(now: Time.current)
    new(now: now).call
  end

  def initialize(now:)
    @now = now
  end

  def call
    start_due_challenges
    begin_finalizing_ended_challenges
    complete_challenges_that_are_ready
  end

  private

  def start_due_challenges
    Challenge.where(status: "published")
             .where("starts_at <= ?", @now)
             .find_each { |challenge| move(challenge, status: "active") }
  end

  def begin_finalizing_ended_challenges
    Challenge.where(status: "active")
             .where("ends_at <= ?", @now)
             .find_each { |challenge| move(challenge, status: "finalizing") }
  end

  def complete_challenges_that_are_ready
    Challenge.where(status: "finalizing")
             .where("ends_at <= ?", @now - FINALIZATION_GRACE)
             .find_each do |challenge|
      # Unreviewed activities mean points could still be lost: wait for an admin.
      next if challenge.unreviewed_activities.exists?

      move(challenge, status: "completed", finalized_at: @now)
    end
  end

  # One broken challenge must not stop the others from moving on.
  def move(challenge, **changes)
    challenge.update!(**changes)
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error(
      "[ChallengeLifecycle] challenge=#{challenge.id} " \
      "could not move to #{changes[:status]}: #{e.message}"
    )
  end
end