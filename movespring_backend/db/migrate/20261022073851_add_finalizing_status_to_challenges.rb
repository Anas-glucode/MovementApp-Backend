# Adds the "finalizing" stage between "active" and "completed", plus the
# moment a challenge was finalised.
#
#   draft -> published -> active -> finalizing -> completed
#                                   (cancelled is possible before the end)
#
# "finalizing" is the cooling-off period after a challenge ends: late syncs
# and admin reviews can still add points, but nobody can join. "completed"
# means the results are final and locked.
class AddFinalizingStatusToChallenges < ActiveRecord::Migration[8.1]
  OLD_STATUSES = "status IN ('draft', 'published', 'active', 'completed', 'cancelled')".freeze
  NEW_STATUSES = "status IN ('draft', 'published', 'active', 'finalizing', 'completed', 'cancelled')".freeze

  def change
    add_column :challenges, :finalized_at, :datetime

    remove_check_constraint :challenges, OLD_STATUSES, name: "challenges_valid_status"
    add_check_constraint :challenges, NEW_STATUSES, name: "challenges_valid_status"
  end
end