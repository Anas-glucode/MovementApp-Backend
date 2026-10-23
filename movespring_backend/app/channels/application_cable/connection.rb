module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      payload = TokenService.decode(request.params[:token].to_s)
      user = payload && User.find_by(id: payload["sub"])

      if user&.active? && user.company.active?
        user
      else
        reject_unauthorized_connection
      end
    end
  end
end