class CreateTeamMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :team_memberships do |t|
      t.references :team, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      # Repeated from the team on purpose: it lets ONE unique index say
      # "a person can be on only one team per challenge".
      t.references :challenge, null: false, foreign_key: true

      t.timestamps
    end

    add_index :team_memberships, [:challenge_id, :user_id],
              unique: true,
              name: "index_team_memberships_on_challenge_and_user"
  end
end