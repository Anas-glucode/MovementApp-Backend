require "test_helper"
require "securerandom"

class ChallengesTest < ActionDispatch::IntegrationTest
  setup do
    @company = create_company("Company A")
    @admin = create_user(@company, role: "company_admin")
    @employee = create_user(@company, role: "employee")

    @other_company = create_company("Company B")
    @other_admin = create_user(@other_company, role: "company_admin")

    @scoring_rules = ScoringRuleVersion
                     .where(status: "published")
                     .order(version_number: :desc)
                     .first

    raise "Test requires a published scoring-rule version" unless @scoring_rules
  end

  test "company administrator can create a draft challenge" do
    assert_difference "Challenge.count", 1 do
      post "/api/v1/challenges",
           params: {
             challenge: {
               name: "October Fitness Challenge",
               description: "Be more active this month",
               starts_at: 2.days.from_now.iso8601,
               ends_at: 9.days.from_now.iso8601
             }
           },
           headers: auth_headers(@admin),
           as: :json
    end

    assert_response :created

    challenge = Challenge.find(response.parsed_body.dig("challenge", "id"))

    assert_equal @company.id, challenge.company_id
    assert_equal @scoring_rules.id, challenge.scoring_rule_version_id
    assert_equal "draft", challenge.status
  end

  test "client cannot choose the company status or scoring rules" do
    post "/api/v1/challenges",
         params: {
           challenge: {
             name: "Protected Challenge",
             starts_at: 2.days.from_now.iso8601,
             ends_at: 9.days.from_now.iso8601,
             company_id: @other_company.id,
             scoring_rule_version_id: 999999,
             status: "active"
           }
         },
         headers: auth_headers(@admin),
         as: :json

    assert_response :created

    challenge = Challenge.find(response.parsed_body.dig("challenge", "id"))

    assert_equal @company.id, challenge.company_id
    assert_equal @scoring_rules.id, challenge.scoring_rule_version_id
    assert_equal "draft", challenge.status
  end

  test "employee cannot create a challenge" do
    assert_no_difference "Challenge.count" do
      post "/api/v1/challenges",
           params: {
             challenge: {
               name: "Unauthorised Challenge",
               starts_at: 2.days.from_now.iso8601,
               ends_at: 9.days.from_now.iso8601
             }
           },
           headers: auth_headers(@employee),
           as: :json
    end

    assert_response :forbidden
  end

  test "administrator can list challenges belonging to their company" do
    own_challenge = create_challenge(@company, status: "draft")
    other_challenge = create_challenge(@other_company, status: "published")

    get "/api/v1/challenges",
        headers: auth_headers(@admin),
        as: :json

    assert_response :ok

    ids = response.parsed_body.fetch("challenges").map { |item| item["id"] }

    assert_includes ids, own_challenge.id
    assert_not_includes ids, other_challenge.id
  end

  test "employee sees published challenges but not drafts" do
    published = create_challenge(@company, status: "published")
    draft = create_challenge(@company, status: "draft")
    create_challenge(@other_company, status: "published")

    get "/api/v1/challenges",
        headers: auth_headers(@employee),
        as: :json

    assert_response :ok

    ids = response.parsed_body.fetch("challenges").map { |item| item["id"] }

    assert_includes ids, published.id
    assert_not_includes ids, draft.id
    assert_equal 1, ids.length
  end

  test "user cannot view another company's challenge" do
    challenge = create_challenge(@other_company, status: "published")

    get "/api/v1/challenges/#{challenge.id}",
        headers: auth_headers(@admin),
        as: :json

    assert_response :not_found
  end

  test "employee cannot view a draft challenge" do
    challenge = create_challenge(@company, status: "draft")

    get "/api/v1/challenges/#{challenge.id}",
        headers: auth_headers(@employee),
        as: :json

    assert_response :not_found
  end

  test "administrator can edit a draft challenge" do
    challenge = create_challenge(@company, status: "draft")

    patch "/api/v1/challenges/#{challenge.id}",
          params: {
            challenge: {
              name: "Updated Challenge",
              description: "Updated description"
            }
          },
          headers: auth_headers(@admin),
          as: :json

    assert_response :ok
    assert_equal "Updated Challenge", challenge.reload.name
    assert_equal "Updated description", challenge.description
  end

  test "published challenge cannot be edited" do
    challenge = create_challenge(@company, status: "published")

    patch "/api/v1/challenges/#{challenge.id}",
          params: {
            challenge: { name: "Attempted Change" }
          },
          headers: auth_headers(@admin),
          as: :json

    assert_response :unprocessable_entity
    assert_equal "Test Challenge", challenge.reload.name
  end

  test "administrator can publish a future draft challenge" do
    challenge = create_challenge(@company, status: "draft")

    patch "/api/v1/challenges/#{challenge.id}/publish",
          headers: auth_headers(@admin),
          as: :json

    assert_response :ok
    assert_equal "published", challenge.reload.status
  end

  test "challenge with a start time in the past cannot be published" do
    challenge = create_challenge(
      @company,
      status: "draft",
      starts_at: 1.hour.ago,
      ends_at: 2.days.from_now
    )

    patch "/api/v1/challenges/#{challenge.id}/publish",
          headers: auth_headers(@admin),
          as: :json

    assert_response :unprocessable_entity
    assert_equal "draft", challenge.reload.status
  end

  test "employee cannot publish a challenge" do
    challenge = create_challenge(@company, status: "draft")

    patch "/api/v1/challenges/#{challenge.id}/publish",
          headers: auth_headers(@employee),
          as: :json

    assert_response :forbidden
    assert_equal "draft", challenge.reload.status
  end

  test "publishing a challenge from another company returns not found" do
    challenge = create_challenge(@other_company, status: "draft")

    patch "/api/v1/challenges/#{challenge.id}/publish",
          headers: auth_headers(@admin),
          as: :json

    assert_response :not_found
    assert_equal "draft", challenge.reload.status
  end

  test "challenge creation fails when no published scoring rules exist" do
    ScoringRuleVersion.where(status: "published")
                      .update_all(status: "retired")

    assert_no_difference "Challenge.count" do
      post "/api/v1/challenges",
           params: {
             challenge: {
               name: "Challenge Without Rules",
               starts_at: 2.days.from_now.iso8601,
               ends_at: 9.days.from_now.iso8601
             }
           },
           headers: auth_headers(@admin),
           as: :json
    end

    assert_response :unprocessable_entity
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
      description: "Integration test challenge",
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
