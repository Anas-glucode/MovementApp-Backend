# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_14_115209) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "activities", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "activity_type", null: false
    t.string "source", null: false
    t.string "source_record_id"
    t.datetime "started_at", null: false
    t.datetime "ended_at", null: false
    t.integer "duration_seconds", null: false
    t.decimal "distance_meters", precision: 12, scale: 2
    t.integer "steps"
    t.decimal "active_calories", precision: 10, scale: 2
    t.integer "average_heart_rate"
    t.string "intensity_source"
    t.integer "reported_intensity"
    t.string "status", default: "pending", null: false
    t.string "review_reason"
    t.datetime "validated_at"
    t.string "time_zone"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "source", "source_record_id"], name: "index_activities_on_unique_source_record", unique: true, where: "(source_record_id IS NOT NULL)"
    t.index ["user_id", "started_at"], name: "index_activities_on_user_and_started_at"
    t.index ["user_id", "status"], name: "index_activities_on_user_and_status"
    t.index ["user_id"], name: "index_activities_on_user_id"
    t.check_constraint "active_calories IS NULL OR active_calories >= 0::numeric", name: "activities_nonnegative_calories"
    t.check_constraint "average_heart_rate IS NULL OR average_heart_rate >= 1 AND average_heart_rate <= 250", name: "activities_valid_heart_rate"
    t.check_constraint "distance_meters IS NULL OR distance_meters >= 0::numeric", name: "activities_nonnegative_distance"
    t.check_constraint "duration_seconds > 0", name: "activities_positive_duration"
    t.check_constraint "ended_at > started_at", name: "activities_valid_time_range"
    t.check_constraint "reported_intensity IS NULL OR reported_intensity >= 1 AND reported_intensity <= 10", name: "activities_valid_reported_intensity"
    t.check_constraint "source::text = ANY (ARRAY['healthkit'::character varying, 'health_connect'::character varying, 'manual'::character varying]::text[])", name: "activities_valid_source"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'eligible'::character varying, 'under_review'::character varying, 'rejected'::character varying]::text[])", name: "activities_valid_status"
    t.check_constraint "steps IS NULL OR steps >= 0", name: "activities_nonnegative_steps"
  end

  create_table "companies", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.string "status", default: "active", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_companies_on_slug", unique: true
  end

  create_table "invitations", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "invited_by_id", null: false
    t.string "email", null: false
    t.string "token_digest", null: false
    t.datetime "expires_at", null: false
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "email"], name: "index_invitations_on_company_id_and_email"
    t.index ["company_id"], name: "index_invitations_on_company_id"
    t.index ["invited_by_id"], name: "index_invitations_on_invited_by_id"
    t.index ["token_digest"], name: "index_invitations_on_token_digest", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.string "name", null: false
    t.string "email", null: false
    t.string "password_digest", null: false
    t.string "role", default: "employee", null: false
    t.string "status", default: "active", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "lower((email)::text)", name: "index_users_on_lower_email", unique: true
    t.index ["company_id"], name: "index_users_on_company_id"
  end

  add_foreign_key "activities", "users"
  add_foreign_key "invitations", "companies"
  add_foreign_key "invitations", "users", column: "invited_by_id"
  add_foreign_key "users", "companies"
end
