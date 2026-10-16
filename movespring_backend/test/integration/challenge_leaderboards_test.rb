require "test_helper"
require "securerandom"

class ChallengeLeaderboardsTest < ActionDispatch::IntegrationTest
  setup do
    @company = create_company("Company A")
    @admin = create_user(@company, role: "company_admin")
    @employee = create_user(@company, role: "employee")
    @second_employee = create_user(@company, role: "employee")
    @zero_point_employee = create_user(@company, role: "employee")

    @other_company = create_company("Company B")
    @other_admin = create_user(@other_company, role: "company_admin")

    @scoring_rules = ScoringRuleVersion
                     .where(status: "published")
                     .where.not(published_at: nil)
                     .order(version_number: :desc)
                     .first

    raise "Test requires published scoring rules" unless @scoring_rules
  end

  test "leaderboard ranks participants and includes employees with zero points" do
    challenge = create_challenge(@company)

    join_challenge(challenge, @employee)
    join_challenge(challenge, @second_employee)
    join_challenge(challenge, @zero_point_employee)

    activate_challenge(challenge)

    create_scored_activity(@employee, challenge, points: 100)
    create_scored_activity(@second_employee, challenge, points: 50)

    get "/api/v1/challenges/#{challenge.id}/leaderboard",
        headers: auth_headers(@employee),
        as: :json

    assert_response :ok

    body = response.parsed_body
    leaderboard = body.fetch("leaderboard")

    assert_equal challenge.id, body["challenge_id"]
    assert_equal @scoring_rules.version_number, body["scoring_rule_version"]
    assert_equal 3, leaderboard.length

    assert_equal @employee.id, leaderboard[0]["user_id"]
    assert_equal 100, leaderboard[0]["points"]
    assert_equal 1, leaderboard[0]["rank"]

    assert_equal @second_employee.id, leaderboard[1]["user_id"]
    assert_equal 50, leaderboard[1]["points"]
    assert_equal 2, leaderboard[1]["rank"]

    assert_equal @zero_point_employee.id, leaderboard[2]["user_id"]
    assert_equal 0, leaderboard[2]["points"]
    assert_equal 3, leaderboard[2]["rank"]

    refute_includes leaderboard.first.keys, "average_heart_rate"
  end

  test "participants with tied scores receive the same rank" do
    challenge = create_challenge(@company)

    join_challenge(challenge, @employee)
    join_challenge(challenge, @second_employee)
    join_challenge(challenge, @zero_point_employee)

    activate_challenge(challenge)

    create_scored_activity(@employee, challenge, points: 100)
    create_scored_activity(@second_employee, challenge, points: 100)
    create_scored_activity(@zero_point_employee, challenge, points: 20)

    get "/api/v1/challenges/#{challenge.id}/leaderboard",
        headers: auth_headers(@employee),
        as: :json

    assert_response :ok

    leaderboard = response.parsed_body.fetch("leaderboard")

    assert_equal [1, 1, 3], leaderboard.map { |entry| entry["rank"] }
    assert_equal [100, 100, 20], leaderboard.map { |entry| entry["points"] }
  end

  test "leaderboard excludes ineligible activities and activities outside the challenge period" do
    challenge = create_challenge(@company)
    join_challenge(challenge, @employee)
    activate_challenge(challenge)

    create_scored_activity(@employee, challenge, points: 100)

    before_activity = create_activity(
      @employee,
      started_at: challenge.starts_at - 2.hours,
      ended_at: challenge.starts_at - 1.hour,
      status: "eligible"
    )
   create_award(before_activity, challenge: challenge, points: 500)

    after_activity = create_activity(
      @employee,
      started_at: challenge.ends_at + 1.hour,
      ended_at: challenge.ends_at + 2.hours,
      status: "eligible"
    )
    create_award(after_activity, challenge: challenge, points: 500)

    pending_activity = create_activity(
      @employee,
      started_at: challenge.starts_at + 3.hours,
      ended_at: challenge.starts_at + 4.hours,
      status: "pending"
    )
    create_award(pending_activity, challenge: challenge, points: 900)

    get "/api/v1/challenges/#{challenge.id}/leaderboard",
        headers: auth_headers(@employee),
        as: :json

    assert_response :ok

    leaderboard = response.parsed_body.fetch("leaderboard")

    assert_equal 1, leaderboard.length
    assert_equal 100, leaderboard.first["points"]
  end

  test "leaderboard excludes awards from a different scoring-rule version" do
    challenge = create_challenge(@company)
    join_challenge(challenge, @employee)
    activate_challenge(challenge)

    create_scored_activity(@employee, challenge, points: 100)

    another_version = create_another_published_version
    activity = create_activity(
      @employee,
      started_at: challenge.starts_at + 5.hours,
      ended_at: challenge.starts_at + 6.hours,
      status: "eligible"
    )

    ActivityPointAward.create!(
      activity: activity,
      scoring_rule_version: another_version,
      points: 700
    )

    get "/api/v1/challenges/#{challenge.id}/leaderboard",
        headers: auth_headers(@employee),
        as: :json

    assert_response :ok

    entry = response.parsed_body.fetch("leaderboard").first
    assert_equal 100, entry["points"]
  end

  test "employee cannot view a draft challenge leaderboard" do
    challenge = create_challenge(@company, status: "draft")

    get "/api/v1/challenges/#{challenge.id}/leaderboard",
        headers: auth_headers(@employee),
        as: :json

    assert_response :not_found
  end

  test "challenge leaderboard cannot be accessed across companies" do
    challenge = create_challenge(@other_company)

    get "/api/v1/challenges/#{challenge.id}/leaderboard",
        headers: auth_headers(@admin),
        as: :json

    assert_response :not_found
  end

  test "company administrator can view their company's leaderboard" do
    challenge = create_challenge(@company)
    join_challenge(challenge, @employee)
    activate_challenge(challenge)

    create_scored_activity(@employee, challenge, points: 75)

    get "/api/v1/challenges/#{challenge.id}/leaderboard",
        headers: auth_headers(@admin),
        as: :json

    assert_response :ok
    assert_equal 75,
                 response.parsed_body.dig("leaderboard", 0, "points")
  end

  private

  def create_company(name)
    Company.create!(
      name: name,
      slug: "#{name.parameterize}-#{SecureRandom.hex(4)}",
      status: "active"
    )
  end

  def create_user(company, role:)
    User.create!(
      company: company,
      name: "Test #{role.humanize} #{SecureRandom.hex(3)}",
      email: "user-#{SecureRandom.hex(8)}@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      role: role,
      status: "active"
    )
  end

  def create_challenge(company, status: "published")
    Challenge.create!(
      company: company,
      scoring_rule_version: @scoring_rules,
      name: "Test Challenge",
      description: "Leaderboard integration test",
      starts_at: 2.days.from_now,
      ends_at: 9.days.from_now,
      status: status
    )
  end

  def join_challenge(challenge, user)
    ChallengeParticipation.create!(
      challenge: challenge,
      user: user
    )
  end

  def activate_challenge(challenge)
    # Participants join while the challenge is upcoming.
    # Move the challenge into its active period for leaderboard testing.
    challenge.update_columns(
      starts_at: 2.days.ago,
      ends_at: 2.days.from_now,
      status: "active"
    )
  end

  def create_activity(user, started_at:, ended_at:, status:)
    Activity.create!(
      user: user,
      activity_type: "walking",
      source: "health_connect",
      started_at: started_at,
      ended_at: ended_at,
      duration_seconds: (ended_at - started_at).to_i,
      status: status
    )
  end


  def create_scored_activity(user, challenge, points:)
    activity = create_activity(
      user,
      started_at: challenge.starts_at + 1.hour,
      ended_at: challenge.starts_at + 2.hours,
      status: "eligible"
    )

    create_award(
      activity,
      challenge: challenge,
      points: points
    )
  end

  def create_award(
    activity,
    challenge:,
    points:,
    scoring_rule_version: challenge.scoring_rule_version
  )
    ChallengeActivityAward.create!(
      challenge: challenge,
      activity: activity,
      scoring_rule_version: scoring_rule_version,
      points: points
    )
  end


  def create_another_published_version
    ScoringRuleVersion.create!(
      name: "Leaderboard Test Rules #{SecureRandom.hex(4)}",
      version_number: ScoringRuleVersion.maximum(:version_number).to_i + 100,
      rules: @scoring_rules.rules.deep_dup,
      status: "published",
      published_at: Time.current
    )
  end

  def auth_headers(user)
    {
      "Authorization" => "Bearer #{TokenService.issue(user)}"
    }
  end
end
