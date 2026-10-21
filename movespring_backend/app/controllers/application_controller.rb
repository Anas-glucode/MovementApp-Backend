class ApplicationController < ActionController::API
  before_action :authenticate_user!

  attr_reader :current_user

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

      return render json: {
        error: "Account is inactive or unavailable"
      }, status: :unauthorized
    end
    
  end
end