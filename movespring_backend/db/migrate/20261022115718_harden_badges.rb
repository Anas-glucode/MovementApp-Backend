   class HardenBadges < ActiveRecord::Migration[8.1]
     def change
       add_foreign_key :badges, :companies

       add_index :badges, :name,
                 unique: true,
                 where: "company_id IS NULL",
                 name: "index_badges_on_name_for_global_badges"
     end
   end