class CreateChallengeParticipations < ActiveRecord::Migration[8.1]
  def change
    create_table :challenge_participations do |t|
      t.references :challenge, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end

    add_index :challenge_participations,
              [:challenge_id, :user_id],
              unique: true,
              name: "index_challenge_participations_on_challenge_and_user"
  end
end
