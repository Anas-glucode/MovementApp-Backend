
require "test_helper"
require "securerandom"
require "json"

class ApiSecurityTest < ActionDispatch::IntegrationTest
  setup do
    @company = create_company("Company A")
    @admin = create_user(
      @company,
      role: "company_admin",
      name: "Company Admin"
    )
    @employee = create_user(
      @company,
      role: "employee",
      name: "Employee One"
    )

    @other_company = create_company("Company B")
    @other_employee = create_user(
      @other_company,
      role: "employee",
      name: "Employee Two"
    )
  end

  test "unauthenticated users cannot access their profile" do
    get "/api/v1/me"

    assert_response :unauthorized
    assert_equal(
      "Authentication token is required",
      JSON.parse(response.body)["error"]
    )
  end

  test "active users can log in" do
    post "/api/v1/sessions",
         params: {
           email: @admin.email,
           password: "Password123!"
         },
         as: :json

    assert_response :ok

    body = JSON.parse(response.body)

    assert_equal "Login successful", body["message"]
    assert body["token"].present?
    assert body["refresh_token"].present?
    assert_equal 1, @admin.refresh_tokens.count
    assert_equal @admin.id, body.dig("user", "id")
  end

  test "refreshing a session rotates the refresh token" do
    old_refresh_token = RefreshTokenService.issue(@admin)

    post "/api/v1/sessions/refresh",
         params: { refresh_token: old_refresh_token },
         as: :json

    assert_response :ok
    body = JSON.parse(response.body)
    assert body["token"].present?
    assert body["refresh_token"].present?
    assert_not_equal old_refresh_token, body["refresh_token"]
    assert_equal 2, @admin.refresh_tokens.count
  end

  test "logging out revokes only the supplied session" do
    refresh_token = RefreshTokenService.issue(@admin)
    other_refresh_token = RefreshTokenService.issue(@admin)

    delete "/api/v1/sessions",
           params: { refresh_token: refresh_token },
           as: :json

    assert_response :no_content
    revoked_token = @admin.refresh_tokens.find_by!(
      token_digest: Digest::SHA256.hexdigest(refresh_token)
    )
    active_token = @admin.refresh_tokens.find_by!(
      token_digest: Digest::SHA256.hexdigest(other_refresh_token)
    )
    assert revoked_token.revoked_at.present?
    assert_nil active_token.revoked_at
  end

  test "logging out everywhere revokes all refresh tokens" do
    RefreshTokenService.issue(@admin)
    RefreshTokenService.issue(@admin)

    delete "/api/v1/sessions/all", headers: auth_headers(@admin)

    assert_response :no_content
    assert_empty @admin.refresh_tokens.where(revoked_at: nil)
  end

  test "inactive users cannot log in" do
    @employee.update!(status: "inactive")

    post "/api/v1/sessions",
         params: {
           email: @employee.email,
           password: "Password123!"
         },
         as: :json

    assert_response :unauthorized
  end

  test "authenticated users can access their own profile" do
    get "/api/v1/me",
        headers: auth_headers(@employee)

    assert_response :ok

    body = JSON.parse(response.body)

    assert_equal @employee.id, body.dig("user", "id")
    assert_equal @employee.company_id, body.dig("user", "company_id")
  end

  test "employees cannot access the employee management endpoint" do
    get "/api/v1/employees",
        headers: auth_headers(@employee)

    assert_response :forbidden
  end

  test "company administrators can only see their own company users" do
    get "/api/v1/employees",
        headers: auth_headers(@admin)

    assert_response :ok

    employee_ids = JSON.parse(response.body)
                           .fetch("employees")
                           .map { |employee| employee["id"] }

    assert_includes employee_ids, @admin.id
    assert_includes employee_ids, @employee.id
    assert_not_includes employee_ids, @other_employee.id
  end

  test "company administrators can create employee invitations" do
    assert_enqueued_emails 1 do
      post "/api/v1/invitations",
           params: {
             invitation: {
               email: unique_email
             }
           },
           headers: auth_headers(@admin),
           as: :json
    end

    assert_response :created

    body = JSON.parse(response.body)

    assert_equal "Invitation created successfully", body["message"]
    assert body.dig("invitation", "id").present?
    assert body["invitation_token"].present?
  end

  test "resending an invitation returns the token outside production and emails it" do
    email = unique_email
    result = InvitationService.call(invited_by: @admin, email: email)
    old_invitation = result.fetch(:invitation)

    assert_enqueued_emails 1 do
      post "/api/v1/invitations/#{old_invitation.id}/resend",
           headers: auth_headers(@admin),
           as: :json
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "Invitation resent", body["message"]
    assert body["invitation_token"].present?
    assert old_invitation.reload.revoked?
  end

  test "employees cannot create employee invitations" do
    post "/api/v1/invitations",
         params: {
           invitation: {
             email: unique_email
           }
         },
         headers: auth_headers(@employee),
         as: :json

    assert_response :forbidden
    assert_equal(
      "Only company administrators can manage invitations",
      response.parsed_body["error"]
    )
  end

  test "employees cannot list, cancel, or resend invitations" do
    result = InvitationService.call(
      invited_by: @admin,
      email: unique_email
    )
    invitation = result.fetch(:invitation)
    headers = auth_headers(@employee)

    get "/api/v1/invitations", headers: headers
    assert_response :forbidden

    delete "/api/v1/invitations/#{invitation.id}", headers: headers
    assert_response :forbidden

    post "/api/v1/invitations/#{invitation.id}/resend", headers: headers
    assert_response :forbidden

    assert_not invitation.reload.revoked?
  end

  test "invitation acceptance creates an employee in the correct company" do
    email = unique_email

    result = InvitationService.call(
      invited_by: @admin,
      email: email
    )

    assert result[:invitation].present?,
           result[:errors].inspect

    post "/api/v1/invitations/accept",
         params: {
           token: result[:token],
           name: "New Employee",
           password: "Password123!",
           password_confirmation: "Password123!"
         },
         as: :json

    assert_response :created

    body = response.parsed_body
    user = User.find_by!(email: email)

    assert body["token"].present?
    assert body["refresh_token"].present?
    assert_equal "Bearer", body["token_type"]
    assert_equal TokenService::LIFETIME.to_i, body["expires_in"]
    assert_equal @company.id, user.company_id
    assert user.employee?
    assert user.active?
    assert_equal user.id, body.dig("user", "id")
    assert result[:invitation].reload.accepted?

    get "/api/v1/me",
        headers: { "Authorization" => "Bearer #{body['token']}" },
        as: :json

    assert_response :ok
    assert_equal user.id, response.parsed_body.dig("user", "id")
  end

  test "invitation tokens cannot be accepted more than once" do
    email = unique_email

    result = InvitationService.call(
      invited_by: @admin,
      email: email
    )

    assert result[:invitation].present?,
           result[:errors].inspect

    acceptance_params = {
      token: result[:token],
      name: "New Employee",
      password: "Password123!",
      password_confirmation: "Password123!"
    }

    post "/api/v1/invitations/accept",
         params: acceptance_params,
         as: :json

    assert_response :created
    assert_equal 1, User.where(email: email).count

    post "/api/v1/invitations/accept",
         params: acceptance_params,
         as: :json

    assert_response :unprocessable_entity
    assert_equal 1, User.where(email: email).count
    assert result[:invitation].reload.accepted?
  end


  test "failed invitation acceptance does not consume the invitation" do
    email = unique_email

    result = InvitationService.call(
      invited_by: @admin,
      email: email
    )

    assert result[:invitation].present?,
           result[:errors].inspect

    invitation = result[:invitation]

    post "/api/v1/invitations/accept",
         params: {
           token: result[:token],
           name: "New Employee",
           password: "Password123!",
           password_confirmation: "DifferentPassword123!"
         },
         as: :json

    assert_response :unprocessable_entity
    assert_nil invitation.reload.accepted_at
    assert_not User.exists?(email: email)
    assert invitation.usable?
  end


  test "invalid invitation tokens are rejected" do
    post "/api/v1/invitations/accept",
         params: {
           token: "invalid-token",
           name: "New Employee",
           password: "Password123!",
           password_confirmation: "Password123!"
         },
         as: :json

    assert_response :unprocessable_entity
  end


  test "users of inactive companies cannot log in" do
    @company.update!(status: "inactive")

    post "/api/v1/sessions",
         params: {
           email: @admin.email,
           password: "Password123!"
         },
         as: :json

    assert_response :unauthorized
  end

  test "administrators cannot invite an existing user's email" do
    post "/api/v1/invitations",
         params: {
           invitation: {
             email: @employee.email
           }
         },
         headers: auth_headers(@admin),
         as: :json

    assert_response :unprocessable_entity

    assert_equal 0, Invitation.where(
      company: @company,
      email: @employee.email
    ).count
  end


  test "administrators cannot create duplicate pending invitations" do
    email = unique_email

    first_result = InvitationService.call(
      invited_by: @admin,
      email: email
    )

    assert first_result[:invitation].present?,
           first_result[:errors].inspect

    post "/api/v1/invitations",
         params: { invitation: { email: email } },
         headers: auth_headers(@admin),
         as: :json

    assert_response :unprocessable_entity

    assert_equal 1,
                 Invitation.where(
                   company: @company,
                   email: email
                 ).pending.count
  end


  test "expired invitations cannot be accepted" do
    email = unique_email

    result = InvitationService.call(
      invited_by: @admin,
      email: email
    )

    assert result[:invitation].present?,
           result[:errors].inspect

    invitation = result[:invitation]
    invitation.update_column(:expires_at, 1.day.ago)

    post "/api/v1/invitations/accept",
         params: {
           token: result[:token],
           name: "Late Employee",
           password: "Password123!",
           password_confirmation: "Password123!"
         },
         as: :json

    assert_response :unprocessable_entity
    assert_not User.exists?(email: email)
    assert_nil invitation.reload.accepted_at
  end

  test "revoked invitations are not pending or usable" do
    email = unique_email
    result = InvitationService.call(invited_by: @admin, email: email)

    assert result[:invitation].present?,
           result[:errors].inspect

    invitation = result[:invitation]
    invitation.update!(revoked_at: Time.current)

    assert invitation.revoked?
    assert_not invitation.usable?
    assert_not Invitation.pending.exists?(id: invitation.id)

    replacement = InvitationService.call(invited_by: @admin, email: email)
    assert replacement[:invitation].present?,
           replacement[:errors].inspect
  end

    test "tampered authentication tokens are rejected" do
    get "/api/v1/me",
        headers: {
          "Authorization" => "Bearer invalid.token.value"
        }

    assert_response :unauthorized
  end

   test "deactivated users cannot use existing authentication tokens" do
    headers = auth_headers(@employee)

    @employee.update!(status: "inactive")

    get "/api/v1/me", headers: headers

    assert_response :unauthorized
  end

  test "users cannot use existing tokens after their company is deactivated" do
    headers = auth_headers(@employee)

    @company.update!(status: "inactive")

    get "/api/v1/me", headers: headers

    assert_response :unauthorized
  end

  test "expired authentication tokens are rejected" do
    expired_token = JWT.encode(
      {
        sub: @employee.id,
        company_id: @employee.company_id,
        role: @employee.role,
        iat: 2.hours.ago.to_i,
        exp: 1.hour.ago.to_i
      },
      Rails.application.secret_key_base,
      "HS256"
    )

    get "/api/v1/me",
        headers: {
          "Authorization" => "Bearer #{expired_token}"
        }

    assert_response :unauthorized
  end


  test "company administrators can update employee details" do
    patch "/api/v1/employees/#{@employee.id}",
          params: {
            employee: {
              name: "Updated Employee",
              email: unique_email
            }
          },
          headers: auth_headers(@admin),
          as: :json

    assert_response :ok

    @employee.reload
    assert_equal "Updated Employee", @employee.name
    assert @employee.employee?
  end

  test "employees cannot update employee details" do
    patch "/api/v1/employees/#{@employee.id}",
          params: {
            employee: {
              name: "Unauthorized Change"
            }
          },
          headers: auth_headers(@employee),
          as: :json

    assert_response :forbidden

    @employee.reload
    assert_equal "Employee One", @employee.name
  end

  test "employees cannot change their own role" do
    patch "/api/v1/employees/#{@employee.id}/role",
          params: { role: "company_admin" },
          headers: auth_headers(@employee),
          as: :json

    assert_response :forbidden
    assert @employee.reload.employee?
  end

  test "employees receive forbidden for role changes and invitation management" do
    result = InvitationService.call(
      invited_by: @admin,
      email: unique_email
    )
    invitation = result.fetch(:invitation)
    headers = auth_headers(@employee)

    patch "/api/v1/employees/#{@employee.id}/role",
          params: { role: "company_admin" },
          headers: headers,
          as: :json
    assert_response :forbidden

    get "/api/v1/invitations", headers: headers
    assert_response :forbidden

    delete "/api/v1/invitations/#{invitation.id}", headers: headers
    assert_response :forbidden

    post "/api/v1/invitations/#{invitation.id}/resend", headers: headers
    assert_response :forbidden

    assert @employee.reload.employee?
    assert_not invitation.reload.revoked?
  end

  test "company administrators can change an employee role" do
    patch "/api/v1/employees/#{@employee.id}/role",
          params: { role: "company_admin" },
          headers: auth_headers(@admin),
          as: :json

    assert_response :ok
    assert @employee.reload.company_admin?
    assert_equal "company_admin", response.parsed_body.dig("employee", "role")
  end

  test "invalid employee roles are rejected" do
    patch "/api/v1/employees/#{@employee.id}/role",
          params: { role: "owner" },
          headers: auth_headers(@admin),
          as: :json

    assert_response :unprocessable_entity
    assert_equal "Invalid role", response.parsed_body["error"]
    assert @employee.reload.employee?
  end

  test "the last active company administrator cannot be demoted" do
    patch "/api/v1/employees/#{@admin.id}/role",
          params: { role: "employee" },
          headers: auth_headers(@admin),
          as: :json

    assert_response :unprocessable_entity
    assert @admin.reload.company_admin?
  end

  test "administrators cannot update employees from another company" do
    patch "/api/v1/employees/#{@other_employee.id}",
          params: {
            employee: {
              name: "Unauthorized Change"
            }
          },
          headers: auth_headers(@admin),
          as: :json

    assert_response :not_found

    @other_employee.reload
    assert_equal "Employee Two", @other_employee.name
  end

  test "company administrators cannot change roles or manage another company's invitations" do
    patch "/api/v1/employees/#{@other_employee.id}/role",
          params: { role: "company_admin" },
          headers: auth_headers(@admin),
          as: :json

    assert_response :not_found
    assert @other_employee.reload.employee?

    result = InvitationService.call(
      invited_by: create_user(@other_company, role: "company_admin", name: "Other Admin"),
      email: unique_email
    )
    other_invitation = result.fetch(:invitation)

    get "/api/v1/invitations", headers: auth_headers(@admin)
    assert_response :ok
    invitation_ids = response.parsed_body.fetch("invitations").map { |item| item["id"] }
    assert_not_includes invitation_ids, other_invitation.id

    delete "/api/v1/invitations/#{other_invitation.id}",
           headers: auth_headers(@admin)
    assert_response :not_found

    post "/api/v1/invitations/#{other_invitation.id}/resend",
         headers: auth_headers(@admin)
    assert_response :not_found

    assert_not other_invitation.reload.revoked?
  end

  test "company administrators can deactivate employees" do
    headers = auth_headers(@employee)

    patch "/api/v1/employees/#{@employee.id}/deactivate",
          headers: auth_headers(@admin)

    assert_response :ok
    assert_equal "inactive", @employee.reload.status

    get "/api/v1/me", headers: headers

    assert_response :unauthorized
  end

  test "employees cannot deactivate other employees" do
    patch "/api/v1/employees/#{@other_employee.id}/deactivate",
          headers: auth_headers(@employee)

    assert_response :forbidden
    assert @other_employee.reload.active?
  end

    test "administrators cannot deactivate employees from another company" do
    patch "/api/v1/employees/#{@other_employee.id}/deactivate",
          headers: auth_headers(@admin)

    assert_response :not_found
    assert @other_employee.reload.active?
  end


  test "the last active company administrator cannot be deactivated" do
    patch "/api/v1/employees/#{@admin.id}/deactivate",
          headers: auth_headers(@admin)

    assert_response :unprocessable_entity
    assert @admin.reload.active?
  end

  test "an administrator can be deactivated if another active administrator remains" do
    second_admin = create_user(
      @company,
      role: "company_admin",
      name: "Second Admin"
    )

    patch "/api/v1/employees/#{@admin.id}/deactivate",
          headers: auth_headers(@admin)

    assert_response :ok
    assert @admin.reload.inactive?
    assert second_admin.reload.active?
  end

  test "company administrators can reactivate inactive employees" do
    @employee.update!(status: "inactive")

    patch "/api/v1/employees/#{@employee.id}/reactivate",
          headers: auth_headers(@admin)

    assert_response :ok
    assert @employee.reload.active?
    assert @employee.employee?
  end

  test "employees cannot reactivate other employees" do
    inactive_employee = create_user(
      @company,
      role: "employee",
      name: "Inactive Employee"
    )
    inactive_employee.update!(status: "inactive")

    patch "/api/v1/employees/#{inactive_employee.id}/reactivate",
          headers: auth_headers(@employee)

    assert_response :forbidden
    assert inactive_employee.reload.inactive?
  end

  test "administrators cannot reactivate employees from another company" do
    @other_employee.update!(status: "inactive")

    patch "/api/v1/employees/#{@other_employee.id}/reactivate",
          headers: auth_headers(@admin)

    assert_response :not_found
    assert @other_employee.reload.inactive?
  end

    test "employees can view their own company profile" do
    get "/api/v1/company", headers: auth_headers(@employee)

    assert_response :ok

    company_data = response.parsed_body.fetch("company")
    assert_equal @company.id, company_data["id"]
    assert_equal @company.name, company_data["name"]
    assert_equal @company.slug, company_data["slug"]
  end

  test "company administrators can view their own company profile" do
    get "/api/v1/company", headers: auth_headers(@admin)

    assert_response :ok
    assert_equal @company.id, response.parsed_body.dig("company", "id")
  end

  test "company administrators can update their company name" do
    patch "/api/v1/company",
          params: { company: { name: "Updated Company Name" } },
          headers: auth_headers(@admin)

    assert_response :ok
    assert_equal "Updated Company Name", @company.reload.name
    assert_equal "Updated Company Name",
                 response.parsed_body.dig("company", "name")
  end

  test "employees cannot update their company details" do
    original_name = @company.name

    patch "/api/v1/company",
          params: { company: { name: "Unauthorized Change" } },
          headers: auth_headers(@employee)

    assert_response :forbidden
    assert_equal original_name, @company.reload.name
  end

  test "company name cannot be blank" do
    original_name = @company.name

    patch "/api/v1/company",
          params: { company: { name: " " } },
          headers: auth_headers(@admin)

    assert_response :unprocessable_entity
    assert_equal original_name, @company.reload.name
  end

  test "company updates cannot change the slug or status" do
    original_slug = @company.slug
    original_status = @company.status

    patch "/api/v1/company",
          params: {
            company: {
              name: "Safe Name Update",
              slug: "unauthorized-slug",
              status: "inactive"
            }
          },
          headers: auth_headers(@admin)

    assert_response :ok

    @company.reload
    assert_equal "Safe Name Update", @company.name
    assert_equal original_slug, @company.slug
    assert_equal original_status, @company.status
  end




  test "unauthenticated users cannot submit activities" do
    activity_count_before = Activity.count
    started_at = 1.hour.ago

    post "/api/v1/activities",
         params: {
           activity: {
             activity_type: "walking",
             started_at: started_at.iso8601,
             ended_at: (started_at + 30.minutes).iso8601,
             distance_meters: 2000
           }
         },
         as: :json

    assert_response :unauthorized
    assert_equal activity_count_before, Activity.count
  end

  test "authenticated employees can submit manual activities" do
    started_at = 1.hour.ago

    post "/api/v1/activities",
         params: {
           activity: {
             activity_type: "walking",
             started_at: started_at.iso8601,
             ended_at: (started_at + 30.minutes).iso8601,
             distance_meters: 2000,
             reported_intensity: 5
           }
         },
         headers: auth_headers(@employee),
         as: :json

    assert_response :created

    body = response.parsed_body
    activity = Activity.find(body.dig("activity", "id"))

    assert_equal @employee.id, activity.user_id
    assert_equal "manual", activity.source
    assert_equal "eligible", activity.status
    assert_equal 1800, activity.duration_seconds
  end

  test "activity submissions cannot override server-controlled fields" do
    started_at = 1.hour.ago

    post "/api/v1/activities",
         params: {
           activity: {
             user_id: @other_employee.id,
             activity_type: "walking",
             source: "health_connect",
             status: "rejected",
             review_reason: "Forged reason",
             points: 999999,
             started_at: started_at.iso8601,
             ended_at: (started_at + 30.minutes).iso8601,
             distance_meters: 2000,
             reported_intensity: 5
           }
         },
         headers: auth_headers(@employee),
         as: :json

    assert_response :created

    body = response.parsed_body
    activity = Activity.find(body.dig("activity", "id"))

    assert_equal @employee.id, activity.user_id
    assert_equal "manual", activity.source
    assert_equal "eligible", activity.status
    assert_nil activity.review_reason
    assert_not activity.attributes.key?("points")
  end


  test "unauthenticated users cannot view activity history" do
    get "/api/v1/activities", as: :json

    assert_response :unauthorized
  end

  test "employees can only view their own activity history" do
    own_activity = Activity.create!(
      user: @employee,
      activity_type: "walking",
      source: "manual",
      started_at: 2.hours.ago,
      ended_at: 90.minutes.ago,
      duration_seconds: 1800,
      status: "eligible",
      validated_at: Time.current,
      time_zone: "Africa/Johannesburg"
    )

    other_activity = Activity.create!(
      user: @other_employee,
      activity_type: "running",
      source: "manual",
      started_at: 1.hour.ago,
      ended_at: 30.minutes.ago,
      duration_seconds: 1800,
      status: "eligible",
      validated_at: Time.current,
      time_zone: "Africa/Johannesburg"
    )

    get "/api/v1/activities",
        headers: auth_headers(@employee),
        as: :json

    assert_response :success

    activity_ids = response.parsed_body.fetch("activities").pluck("id")

    assert_includes activity_ids, own_activity.id
    assert_not_includes activity_ids, other_activity.id
  end


  private

  def create_company(name)
    Company.create!(
      name: name,
      slug: "#{name.parameterize}-#{SecureRandom.hex(4)}",
      status: "active"
    )
  end

  def create_user(company, role:, name:)
    User.create!(
      company: company,
      name: name,
      email: unique_email,
      password: "Password123!",
      password_confirmation: "Password123!",
      role: role,
      status: "active"
    )
  end

  def unique_email
    "user-#{SecureRandom.hex(8)}@example.com"
  end

  def auth_headers(user)
    {
      "Authorization" => "Bearer #{TokenService.issue(user)}"
    }
  end
end
