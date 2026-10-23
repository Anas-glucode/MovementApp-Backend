class CreateTeams < ActiveRecord::Migration[8.1]
  def change
    create_table :teams do |t|
      t.references :challenge, null: false, foreign_key: true
      t.string :name, null: false

      t.timestamps
    end

    # No two teams in the same challenge may share a name
    add_index :teams, [:challenge_id, :name], unique: true
  end
end