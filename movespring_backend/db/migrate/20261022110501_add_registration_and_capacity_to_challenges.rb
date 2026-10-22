# Two optional settings from the requirements:
#   registration_deadline  the last moment people can join. Empty means
#                          "until the challenge starts", so existing
#                          challenges behave exactly as before.
#   max_participants       the most people allowed to join. Empty means no limit.
class AddRegistrationAndCapacityToChallenges < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :challenges,
                         "max_participants IS NULL OR max_participants > 0",
                         name: "challenges_positive_max_participants"

    add_check_constraint :challenges,
                         "registration_deadline IS NULL OR registration_deadline <= starts_at",
                         name: "challenges_deadline_before_start"
  end
end