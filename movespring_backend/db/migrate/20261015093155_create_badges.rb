class CreateBadges < ActiveRecord::Migration[8.0]
  def change
    create_table :badges do |t|
      t.bigint :company_id, null: true # Nullable if global badge, scoped if company-specific
      t.string :name, null: false
      t.text :description
      t.string :category, null: false # e.g., steps, distance, streak
      t.string :criteria_type, null: false # e.g., single_activity, cumulative
      t.decimal :criteria_value, precision: 12, scale: 2, null: false
      t.string :icon_url

      t.timestamps
    end

    add_index :badges, [:company_id, :category]
    add_index :badges, [:company_id, :name], unique: true
  end
end