# Each company gets ONE time zone. It decides where "midnight" falls for the
# daily point cap, like a shop's closing time: the shop sets it, the
# customer can't claim a different one. Existing companies start on UTC;
# set the right zone for each company afterwards (see the console line in
# the notes).
class AddTimeZoneToCompanies < ActiveRecord::Migration[8.1]
  def change
    add_column :companies, :time_zone, :string, null: false, default: "UTC"
  end
end