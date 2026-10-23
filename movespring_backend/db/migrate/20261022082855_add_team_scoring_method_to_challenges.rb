   class AddTeamScoringMethodToChallenges < ActiveRecord::Migration[8.1]
     def change
       add_column :challenges, :team_scoring_method, :string, null: false, default: "average"

       add_check_constraint :challenges,
                            "team_scoring_method IN ('average', 'total')",
                            name: "challenges_valid_team_scoring_method"
     end
   end