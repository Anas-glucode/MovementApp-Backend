class AddChallengeTypeToChallenges < ActiveRecord::Migration[8.1]
  def change
    # Every existing challenge becomes "individual" automatically
    add_column :challenges, :challenge_type, :string, null: false, default: "individual"

    add_check_constraint :challenges,
                         "challenge_type IN ('individual', 'team')",
                         name: "challenges_valid_type"
  end
end