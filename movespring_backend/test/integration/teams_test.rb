
require "test_helper"
require "securerandom"

class TeamsTest < ActionDispatch::IntegrationTest
  setup do
    @company = create_company("Company A")
    @admin = create_user(@company, role: "company_admin")
    @employee = create_user(@company, role: "employee")
    @employee_two = create_user(@company, role: "employee")
    @employee_three = create_user(@company, role: "employee")
    @employee_four = create_user(@company, role: "employee")

    @other_company = create_company("Company B")
    @other_admin = create_user(@other_company, role: "company_admin")

    @scoring_rules = ScoringRuleVersion
                     .where(status: "published")
                     .order(version_number: :desc)
                     .first

    raise "Test requires a published scoring-rule version" unless @scoring_rules

    @challenge = create_team_challenge
  end

  test "company admin can form teams for a team challenge" do
    join_all_employees

    post "/api/v1/challenges/#{@challenge.id}/teams",
         params: { team_count: 2 },
         headers: auth_headers(@admin)

    assert_response :created

    body = response.parsed_body

    assert_equal "Teams formed successfully", body["message"]
    assert_equal 2, body["teams"].length

    body["teams"].each do |team|
      assert team["id"].present?
      assert team["name"].present?
      assert_equal @challenge.id, team["challenge_id"]
      assert team["members"].present?
    end

    assert_equal 4, body["teams"].sum { |team| team["members"].length }
  end

  test "employee cannot form teams" do
    post "/api/v1/challenges/#{@challenge.id}/teams",
         params: { team_count: 2 },
         headers: auth_headers(@employee)

    assert_response :forbidden
    assert_equal(
      "Only company administrators can form teams",
      response.parsed_body["error"]
    )
  end

  test "employee can view the team leaderboard" do
    join_all_employees
    form_teams

    get "/api/v1/challenges/#{@challenge.id}/teams",
        headers: auth_headers(@employee)

    assert_response :ok

    body = response.parsed_body

    assert_equal @challenge.id, body["challenge_id"]
    assert_equal @challenge.name, body["challenge_name"]
    assert_equal "team", body["challenge_type"]
    assert_equal "average", body["scoring_method"]
    assert_equal 2, body["leaderboard"].length

    body["leaderboard"].each do |team|
      assert team["team_id"].present?
      assert team["name"].present?
      assert team.key?("member_count")
      assert team.key?("points")
      assert team.key?("average_points")
    end
  end

  test "employee can view their own team" do
    join_all_employees
    form_teams

    get "/api/v1/challenges/#{@challenge.id}/my_team",
        headers: auth_headers(@employee)

    assert_response :ok

    body = response.parsed_body
    team = body["team"]

    assert team.present?
    assert team["id"].present?
    assert team["name"].present?
    assert_equal @challenge.id, team["challenge_id"]
    assert team["members"].present?
    assert team.key?("points")
    assert team.key?("goal")
  end

  test "employee receives not found when they do not have a team" do
    get "/api/v1/challenges/#{@challenge.id}/my_team",
        headers: auth_headers(@employee)

    assert_response :not_found

    assert_equal(
      "You are not on a team in this challenge",
      response.parsed_body["error"]
    )
  end

  test "employee cannot view leaderboard for a draft challenge" do
    draft_challenge = create_team_challenge(status: "draft")

    get "/api/v1/challenges/#{draft_challenge.id}/teams",
        headers: auth_headers(@employee)

    assert_response :not_found
  end

  test "another company's admin cannot access this company's challenge" do
    get "/api/v1/challenges/#{@challenge.id}/teams",
        headers: auth_headers(@other_admin)

    assert_response :not_found
  end

  test "another company's admin cannot form teams for this company's challenge" do
    post "/api/v1/challenges/#{@challenge.id}/teams",
         params: { team_count: 2 },
         headers: auth_headers(@other_admin)

    assert_response :not_found
  end

  test "team formation returns an error when there are not enough participants" do
    join_challenge(@employee)

    post "/api/v1/challenges/#{@challenge.id}/teams",
         params: { team_count: 2 },
         headers: auth_headers(@admin)

    assert_response :unprocessable_entity
    assert response.parsed_body["errors"].present?
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

  def create_team_challenge(status: "published")
    Challenge.create!(
      company: @company,
      scoring_rule_version: @scoring_rules,
      name: "Team Challenge #{SecureRandom.hex(3)}",
      description: "Team integration test challenge",
      starts_at: 2.days.from_now,
      ends_at: 9.days.from_now,
      status: status,
      challenge_type: "team",
      team_scoring_method: "average",
      team_goal_points: 100
    )
  end

  def join_challenge(user)
    post "/api/v1/challenges/#{@challenge.id}/join",
         headers: auth_headers(user)

    assert_response :success
  end

  def join_all_employees
    [
      @employee,
      @employee_two,
      @employee_three,
      @employee_four
    ].each do |user|
      join_challenge(user)
    end
  end

  def form_teams
    post "/api/v1/challenges/#{@challenge.id}/teams",
         params: { team_count: 2 },
         headers: auth_headers(@admin)

    assert_response :created
  end

  def auth_headers(user)
    {
      "Authorization" => "Bearer #{TokenService.issue(user)}"
    }
  end
end
