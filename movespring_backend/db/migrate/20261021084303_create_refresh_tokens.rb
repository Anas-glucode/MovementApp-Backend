class CreateRefreshTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :refresh_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token_digest, null: false   # we store a hash, never the real token
      t.string :family_id, null: false      # groups tickets from one login together
      t.datetime :expires_at, null: false
      t.datetime :revoked_at                # set when used, logged out, or cancelled

      t.timestamps
    end

    add_index :refresh_tokens, :token_digest, unique: true
    add_index :refresh_tokens, :family_id
  end
end