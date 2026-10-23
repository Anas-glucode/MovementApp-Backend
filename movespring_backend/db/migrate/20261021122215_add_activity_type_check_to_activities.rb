# The model already limits which sports are allowed. This adds the SAME rule
# inside the database, like a bouncer at the door AND a lock on the vault:
# even code that skips the model (update_all, raw SQL, a console typo)
# cannot save an unknown sport.
#
# NOTE: if any existing row has another activity_type, this migration fails.
# Check first:  Activity.where.not(activity_type: Activity::TYPES).count
class AddActivityTypeCheckToActivities < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :activities,
                         "activity_type IN ('walking', 'running', 'cycling', 'swimming', " \
                         "'football', 'strength_training', 'golf')",
                         name: "activities_valid_activity_type"
  end
end