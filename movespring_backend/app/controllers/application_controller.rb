class ApplicationController < ActionController::API
  before_action :authenticate_user!

  attr_reader :current_user

  # Friendly, consistent JSON for two very common client mistakes.
  #
  # We deliberately do NOT add a catch-all "rescue StandardError" here. A
  # catch-all would hide real bugs behind a polite message. Genuine bugs should
  # stay loud (a 500 that is logged), and you should connect an error tracker
  # (Sentry, Honeybadger, ...) so you hear about them.
  rescue_from ActionController::ParameterMissing do |error|
    render json: { error: "Missing required parameter: #{error.param}" },
           status: :bad_request
  end

  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: "Not found" }, status: :not_found
  end

  private

  def authenticate_user!
    header = request.headers["Authorization"]

    unless header.present? && header.start_with?("Bearer ")
      return render json: {
        error: "Authentication token is required"
      }, status: :unauthorized
    end

    token = header.delete_prefix("Bearer ").strip
    payload = TokenService.decode(token)

    unless payload
      return render json: {
        error: "Invalid or expired authentication token"
      }, status: :unauthorized
    end

    @current_user = User.find_by(id: payload["sub"])

    unless @current_user && ActiveSupport::SecurityUtils.secure_compare(
      @current_user.password_salt.last(10), payload["pwd"].to_s
    )
      @current_user = nil
      return render json: { error: "Invalid or expired authentication token" },
                    status: :unauthorized
    end

    unless @current_user&.active? && @current_user.company.active?
      @current_user = nil

      render json: {
        error: "Account is inactive or unavailable"
      }, status: :unauthorized
    end
  end
end