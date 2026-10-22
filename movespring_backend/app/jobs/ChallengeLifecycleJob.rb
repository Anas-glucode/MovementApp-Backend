# Runs the challenge lifecycle cues. Schedule it every few minutes
# (see config/recurring.yml in the notes).
class ChallengeLifecycleJob < ApplicationJob
  queue_as :default

  def perform
    ChallengeLifecycleService.call
  end
end