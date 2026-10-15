require "test_helper"
require "securerandom"

class ChallengeParticipationsTest < ActionDispatch::IntegrationTest
  setup do
    @company = create_company("Company A")
    @employee = create_user(@company, role: "employee")
    @admin = create_user(@company, role: "company_admin")

    @other_company = create_company("Company B")
    @other_employee = create_user(@other_company, role: "employee")

    @scoring_rules = ScoringRuleVersion
                     .where(status: "published")
                     .order(version_number: :desc)
                     .first

    raise "Test requires published scoring rules" unless @scoring_rules

    @challenge = create_challenge(@company, status: "published")
  end

  test "employee can join a published challenge in their company" do
    assert_difference "ChallengeParticipation.count", 1 do
      post "/api/v1/challenges/#{@challenge.id}/join",
           headers: auth_headers(@employee),
           as: :json
    end

    assert_response :created

    body = response.parsed_body
    assert_equal @challenge.id, body.dig("participation", "challenge_id")
    assert_equal "published", body.dig("challenge", "status")
    assert @employee.joined_challenges.exists?(id: @challenge.id)
  end

  test "employee cannot join the same challenge twice" do
    ChallengeParticipation.create!(
      challenge: @challenge,
      user: @employee
    )

    assert_no_difference "ChallengeParticipation.count" do
      post "/api/v1/challenges/#{@challenge.id}/join",
           headers: auth_headers(@employee),
           as: :json
    end

    assert_response :conflict
  end

  test "employee cannot join a draft challenge" do
    draft = create_challenge(@company, status: "draft")

    assert_no_difference "ChallengeParticipation.count" do
      post "/api/v1/challenges/#{draft.id}/join",
           headers: auth_headers(@employee),
           as: :json
    end

    assert_response :unprocessable_entity
  end

  test "employee cannot join a challenge that has already started" do
    started = create_challenge(
      @company,
      status: "published",
      starts_at: 1.hour.ago,
      ends_at: 2.days.from_now
    )

    assert_no_difference "ChallengeParticipation.count" do
      post "/api/v1/challenges/#{started.id}/join",
           headers: auth_headers(@employee),
           as: :json
    end

    assert_response :unprocessable_entity
  end

  test "employee cannot join another company's challenge" do
    other_challenge = create_challenge(
      @other_company,
      status: "published"
    )

    assert_no_difference "ChallengeParticipation.count" do
      post "/api/v1/challenges/#{other_challenge.id}/join",
           headers: auth_headers(@employee),
           as: :json
    end

    assert_response :not_found
  end

  test "company administrator cannot join as an employee" do
    assert_no_difference "ChallengeParticipation.count" do
      post "/api/v1/challenges/#{@challenge.id}/join",
           headers: auth_headers(@admin),
           as: :json
    end

    assert_response :forbidden
  end

  test "employee can see only challenges they joined" do
    another_challenge = create_challenge(@company, status: "published")

    ChallengeParticipation.create!(
      challenge: @challenge,
      user: @employee
    )

    ChallengeParticipation.create!(
      challenge: another_challenge,
      user: create_user(@company, role: "employee")
    )

    create_challenge(@other_company, status: "published")

    get "/api/v1/my_challenges",
        headers: auth_headers(@employee),
        as: :json

    assert_response :ok

    challenges = response.parsed_body.fetch("challenges")
    ids = challenges.map { |item| item["id"] }

    assert_equal [@challenge.id], ids
  end

  test "employee with no joined challenges receives an empty list" do
    get "/api/v1/my_challenges",
        headers: auth_headers(@employee),
        as: :json

    assert_response :ok
    assert_equal [], response.parsed_body.fetch("challenges")
  end

  test "company administrator cannot use my challenges endpoint" do
    get "/api/v1/my_challenges",
        headers: auth_headers(@admin),
        as: :json

    assert_response :forbidden
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
      name: "Test #{role.humanize}",
      email: "user-#{SecureRandom.hex(8)}@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      role: role,
      status: "active"
    )
  end

  def create_challenge(
    company,
    status: "draft",
    starts_at: 2.days.from_now,
    ends_at: 9.days.from_now
  )
    Challenge.create!(
      company: company,
      scoring_rule_version: @scoring_rules,
      name: "Test Challenge",
      description: "Participation integration test",
      starts_at: starts_at,
      ends_at: ends_at,
      status: status
    )
  end

  def auth_headers(user)
    {
      "Authorization" => "Bearer #{TokenService.issue(user)}"
    }
  end
end
