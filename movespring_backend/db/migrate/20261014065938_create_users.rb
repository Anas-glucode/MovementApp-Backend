class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.references :company, null: false, foreign_key: true
      t.string :name, null: false
      t.string :email, null: false
      t.string :password_digest, null: false
      t.string :role, null: false, default: "employee"
      t.string :status, null: false, default: "active"

      t.timestamps
    end

    add_index :users, "LOWER(email)", unique: true,
              name: "index_users_on_lower_email"
  end
end
