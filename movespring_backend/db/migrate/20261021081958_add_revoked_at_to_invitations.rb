class AddRevokedAtToInvitations < ActiveRecord::Migration[8.1]
  def change
    add_column :invitations, :revoked_at, :datetime
  end
end
