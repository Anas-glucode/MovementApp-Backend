class AddTeamGoalPointsToChallenges < ActiveRecord::Migration[8.1]
  def change
    # Optional target (null = no goal). Existing challenges simply have none.
    add_column :challenges, :team_goal_points, :integer

    # The database refuses zero or negative goals, even if app code forgets
    add_check_constraint :challenges,
                         "team_goal_points IS NULL OR team_goal_points > 0",
                         name: "challenges_positive_team_goal"
  end
end