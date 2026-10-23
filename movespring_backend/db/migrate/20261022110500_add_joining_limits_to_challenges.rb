class AddJoiningLimitsToChallenges < ActiveRecord::Migration[8.1]
  def change
    add_column :challenges, :registration_deadline, :datetime
    add_column :challenges, :max_participants, :integer
  end
end
