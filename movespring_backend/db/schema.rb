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

ActiveRecord::Schema[8.1].define(version: 2026_10_19_075156) do
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
    t.check_constraint "source::text = ANY (ARRAY['healthkit'::character varying::text, 'health_connect'::character varying::text, 'manual'::character varying::text])", name: "activities_valid_source"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'eligible'::character varying::text, 'under_review'::character varying::text, 'rejected'::character varying::text])", name: "activities_valid_status"
    t.check_constraint "steps IS NULL OR steps >= 0", name: "activities_nonnegative_steps"
  end

  create_table "activity_point_awards", force: :cascade do |t|
    t.bigint "activity_id", null: false
    t.bigint "scoring_rule_version_id", null: false
    t.integer "points", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["activity_id"], name: "index_activity_point_awards_on_activity_id", unique: true
    t.index ["scoring_rule_version_id"], name: "index_activity_point_awards_on_scoring_rule_version_id"
    t.check_constraint "points >= 0", name: "activity_point_awards_nonnegative_points"
  end

  create_table "activity_reviews", force: :cascade do |t|
    t.bigint "activity_id", null: false
    t.bigint "reviewer_id", null: false
    t.string "decision", null: false
    t.text "reason"
    t.datetime "reviewed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["activity_id"], name: "index_activity_reviews_on_activity_id", unique: true
    t.index ["reviewer_id"], name: "index_activity_reviews_on_reviewer_id"
    t.check_constraint "decision::text <> 'rejected'::text OR length(TRIM(BOTH FROM reason)) > 0", name: "activity_reviews_rejection_requires_reason"
    t.check_constraint "decision::text = ANY (ARRAY['approved'::character varying::text, 'rejected'::character varying::text])", name: "activity_reviews_valid_decision"
  end

  create_table "badges", force: :cascade do |t|
    t.bigint "company_id"
    t.string "name", null: false
    t.text "description"
    t.string "category", null: false
    t.string "criteria_type", null: false
    t.decimal "criteria_value", precision: 12, scale: 2, null: false
    t.string "icon_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "category"], name: "index_badges_on_company_id_and_category"
    t.index ["company_id", "name"], name: "index_badges_on_company_id_and_name", unique: true
  end

  create_table "challenge_activity_awards", force: :cascade do |t|
    t.bigint "challenge_id", null: false
    t.bigint "activity_id", null: false
    t.bigint "scoring_rule_version_id", null: false
    t.integer "points", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["activity_id"], name: "index_challenge_activity_awards_on_activity_id"
    t.index ["challenge_id", "activity_id"], name: "index_challenge_activity_awards_on_challenge_and_activity", unique: true
    t.index ["challenge_id"], name: "index_challenge_activity_awards_on_challenge_id"
    t.index ["scoring_rule_version_id"], name: "index_challenge_activity_awards_on_scoring_rule_version_id"
    t.check_constraint "points >= 0", name: "challenge_activity_awards_nonnegative_points"
  end

  create_table "challenge_participations", force: :cascade do |t|
    t.bigint "challenge_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["challenge_id", "user_id"], name: "index_challenge_participations_on_challenge_and_user", unique: true
    t.index ["challenge_id"], name: "index_challenge_participations_on_challenge_id"
    t.index ["user_id"], name: "index_challenge_participations_on_user_id"
  end

  create_table "challenges", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "scoring_rule_version_id", null: false
    t.string "name", null: false
    t.text "description"
    t.datetime "starts_at", null: false
    t.datetime "ends_at", null: false
    t.string "status", default: "draft", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "starts_at"], name: "index_challenges_on_company_id_and_starts_at"
    t.index ["company_id", "status"], name: "index_challenges_on_company_id_and_status"
    t.index ["company_id"], name: "index_challenges_on_company_id"
    t.index ["scoring_rule_version_id"], name: "index_challenges_on_scoring_rule_version_id"
    t.check_constraint "ends_at > starts_at", name: "challenges_valid_dates"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'published'::character varying::text, 'active'::character varying::text, 'completed'::character varying::text, 'cancelled'::character varying::text])", name: "challenges_valid_status"
  end

  create_table "chat_rooms", force: :cascade do |t|
    t.bigint "challenge_id", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["challenge_id"], name: "index_chat_rooms_on_challenge_id", unique: true
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

  create_table "messages", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "chat_room_id", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["chat_room_id", "created_at"], name: "index_messages_on_chat_room_id_and_created_at"
    t.index ["chat_room_id"], name: "index_messages_on_chat_room_id"
    t.index ["user_id"], name: "index_messages_on_user_id"
  end

  create_table "scoring_rule_versions", force: :cascade do |t|
    t.string "name", null: false
    t.integer "version_number", null: false
    t.string "status", default: "draft", null: false
    t.jsonb "rules", default: {}, null: false
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["version_number"], name: "index_scoring_rule_versions_on_version_number", unique: true
    t.check_constraint "jsonb_typeof(rules) = 'object'::text", name: "scoring_rule_versions_rules_must_be_object"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'published'::character varying::text, 'retired'::character varying::text])", name: "scoring_rule_versions_valid_status"
    t.check_constraint "version_number > 0", name: "scoring_rule_versions_positive_version"
  end

  create_table "user_badges", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "badge_id", null: false
    t.bigint "activity_id"
    t.datetime "earned_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["activity_id"], name: "index_user_badges_on_activity_id"
    t.index ["badge_id"], name: "index_user_badges_on_badge_id"
    t.index ["user_id", "badge_id"], name: "index_user_badges_on_user_id_and_badge_id", unique: true
    t.index ["user_id"], name: "index_user_badges_on_user_id"
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
  add_foreign_key "activity_point_awards", "activities"
  add_foreign_key "activity_point_awards", "scoring_rule_versions"
  add_foreign_key "activity_reviews", "activities"
  add_foreign_key "activity_reviews", "users", column: "reviewer_id"
  add_foreign_key "challenge_activity_awards", "activities"
  add_foreign_key "challenge_activity_awards", "challenges"
  add_foreign_key "challenge_activity_awards", "scoring_rule_versions"
  add_foreign_key "challenge_participations", "challenges"
  add_foreign_key "challenge_participations", "users"
  add_foreign_key "challenges", "companies"
  add_foreign_key "challenges", "scoring_rule_versions"
  add_foreign_key "chat_rooms", "challenges"
  add_foreign_key "invitations", "companies"
  add_foreign_key "invitations", "users", column: "invited_by_id"
  add_foreign_key "messages", "chat_rooms"
  add_foreign_key "messages", "users"
  add_foreign_key "user_badges", "activities"
  add_foreign_key "user_badges", "badges"
  add_foreign_key "user_badges", "users"
  add_foreign_key "users", "companies"
end
