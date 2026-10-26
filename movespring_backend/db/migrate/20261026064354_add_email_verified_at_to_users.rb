class AddEmailVerifiedAtToUsers < ActiveRecord::Migration[8.1]
  def up
    # NULL means "hasn't proven they own this inbox yet"
    add_column :users, :email_verified_at, :datetime, if_not_exists: true

    # Everyone who already exists is grandfathered in. Without this line,
    # every current user would be locked out the moment you deploy.
    execute "UPDATE users SET email_verified_at = NOW() WHERE email_verified_at IS NULL"
  end

  def down
    remove_column :users, :email_verified_at
  end
end