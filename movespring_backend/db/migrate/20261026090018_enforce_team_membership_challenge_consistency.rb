class EnforceTeamMembershipChallengeConsistency < ActiveRecord::Migration[8.1]
  def up
    add_index :teams,
              [:id, :challenge_id],
              unique: true,
              name: "index_teams_on_id_and_challenge_id"

    add_foreign_key :team_memberships,
                    :teams,
                    column: [:team_id, :challenge_id],
                    primary_key: [:id, :challenge_id],
                    name: "fk_team_memberships_team_challenge_consistency"
  end

  def down
    remove_foreign_key :team_memberships,
                       name: "fk_team_memberships_team_challenge_consistency"

    remove_index :teams,
                 name: "index_teams_on_id_and_challenge_id"
  end
end
