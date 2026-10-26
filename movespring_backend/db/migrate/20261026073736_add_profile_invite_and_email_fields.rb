class AddProfileInviteAndEmailFields < ActiveRecord::Migration[8.1]
  def change
    # --- Users: a "waiting room" for an email change ---
    # The old email stays active until the owner of the NEW inbox clicks
    # the confirmation link. Like a forwarding request at the post office:
    # nothing changes until the new address confirms it.
    add_column :users, :unconfirmed_email, :string, if_not_exists: true

    # --- Invitations: which role the new person will get ---
    # Existing invitations are all "employee", which is what they always were.
    add_column :invitations, :role, :string, null: false, default: "employee",
               if_not_exists: true
    add_check_constraint :invitations,
                         "role IN ('employee', 'company_admin')",
                         name: "invitations_valid_role",
                         if_not_exists: true

    # --- Invitations: did the email actually go out? ---
    # NULL means "not delivered (yet)". The admin's screen can use this.
    add_column :invitations, :email_sent_at, :datetime, if_not_exists: true
  end
end