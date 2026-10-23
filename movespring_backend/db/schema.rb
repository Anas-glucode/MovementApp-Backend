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

ActiveRecord::Schema[8.1].define(version: 2026_10_22_121900) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

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
    t.check_constraint "activity_type::text = ANY (ARRAY['walking'::character varying, 'running'::character varying, 'cycling'::character varying, 'swimming'::character varying, 'football'::character varying, 'strength_training'::character varying, 'golf'::character varying]::text[])", name: "activities_valid_activity_type"
    t.check_constraint "average_heart_rate IS NULL OR average_heart_rate >= 1 AND average_heart_rate <= 250", name: "activities_valid_heart_rate"
    t.check_constraint "distance_meters IS NULL OR distance_meters >= 0::numeric", name: "activities_nonnegative_distance"
    t.check_constraint "duration_seconds > 0", name: "activities_positive_duration"
    t.check_constraint "ended_at > started_at", name: "activities_valid_time_range"
    t.check_constraint "reported_intensity IS NULL OR reported_intensity >= 1 AND reported_intensity <= 10", name: "activities_valid_reported_intensity"
    t.check_constraint "source::text = ANY (ARRAY['healthkit'::character varying, 'health_connect'::character varying, 'manual'::character varying]::text[])", name: "activities_valid_source"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'eligible'::character varying, 'under_review'::character varying, 'rejected'::character varying]::text[])", name: "activities_valid_status"
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
    t.check_constraint "decision::text = ANY (ARRAY['approved'::character varying, 'rejected'::character varying]::text[])", name: "activity_reviews_valid_decision"
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
    t.index ["name"], name: "index_badges_on_name_for_global_badges", unique: true, where: "(company_id IS NULL)"
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
    t.string "challenge_type", default: "individual", null: false
    t.integer "team_goal_points"
    t.datetime "finalized_at"
    t.string "team_scoring_method", default: "average", null: false
    t.datetime "registration_deadline"
    t.integer "max_participants"
    t.index ["company_id", "starts_at"], name: "index_challenges_on_company_id_and_starts_at"
    t.index ["company_id", "status"], name: "index_challenges_on_company_id_and_status"
    t.index ["company_id"], name: "index_challenges_on_company_id"
    t.index ["scoring_rule_version_id"], name: "index_challenges_on_scoring_rule_version_id"
    t.check_constraint "challenge_type::text = ANY (ARRAY['individual'::character varying, 'team'::character varying]::text[])", name: "challenges_valid_type"
    t.check_constraint "ends_at > starts_at", name: "challenges_valid_dates"
    t.check_constraint "max_participants IS NULL OR max_participants > 0", name: "challenges_positive_max_participants"
    t.check_constraint "registration_deadline IS NULL OR registration_deadline <= starts_at", name: "challenges_deadline_before_start"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying, 'published'::character varying, 'active'::character varying, 'finalizing'::character varying, 'completed'::character varying, 'cancelled'::character varying]::text[])", name: "challenges_valid_status"
    t.check_constraint "team_goal_points IS NULL OR team_goal_points > 0", name: "challenges_positive_team_goal"
    t.check_constraint "team_scoring_method::text = ANY (ARRAY['average'::character varying, 'total'::character varying]::text[])", name: "challenges_valid_team_scoring_method"
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
    t.string "time_zone", default: "UTC", null: false
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
    t.datetime "revoked_at"
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

  create_table "refresh_tokens", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "token_digest", null: false
    t.string "family_id", null: false
    t.datetime "expires_at", null: false
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["family_id"], name: "index_refresh_tokens_on_family_id"
    t.index ["token_digest"], name: "index_refresh_tokens_on_token_digest", unique: true
    t.index ["user_id"], name: "index_refresh_tokens_on_user_id"
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
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying, 'published'::character varying, 'retired'::character varying]::text[])", name: "scoring_rule_versions_valid_status"
    t.check_constraint "version_number > 0", name: "scoring_rule_versions_positive_version"
  end

  create_table "team_memberships", force: :cascade do |t|
    t.bigint "team_id", null: false
    t.bigint "user_id", null: false
    t.bigint "challenge_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["challenge_id", "user_id"], name: "index_team_memberships_on_challenge_and_user", unique: true
    t.index ["challenge_id"], name: "index_team_memberships_on_challenge_id"
    t.index ["team_id"], name: "index_team_memberships_on_team_id"
    t.index ["user_id"], name: "index_team_memberships_on_user_id"
  end

  create_table "teams", force: :cascade do |t|
    t.bigint "challenge_id", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["challenge_id", "name"], name: "index_teams_on_challenge_id_and_name", unique: true
    t.index ["challenge_id"], name: "index_teams_on_challenge_id"
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

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "activities", "users"
  add_foreign_key "activity_point_awards", "activities"
  add_foreign_key "activity_point_awards", "scoring_rule_versions"
  add_foreign_key "activity_reviews", "activities"
  add_foreign_key "activity_reviews", "users", column: "reviewer_id"
  add_foreign_key "badges", "companies"
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
  add_foreign_key "refresh_tokens", "users"
  add_foreign_key "team_memberships", "challenges"
  add_foreign_key "team_memberships", "teams"
  add_foreign_key "team_memberships", "users"
  add_foreign_key "teams", "challenges"
  add_foreign_key "user_badges", "activities"
  add_foreign_key "user_badges", "badges"
  add_foreign_key "user_badges", "users"
  add_foreign_key "users", "companies"
end
