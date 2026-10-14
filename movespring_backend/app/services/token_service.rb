
class TokenService
  LIFETIME = 30.minutes

  def self.issue(user)
    now = Time.current.to_i

    payload = {
      sub: user.id,
      company_id: user.company_id,
      role: user.role,
      iat: now,
      exp: (Time.current + LIFETIME).to_i
    }

    JWT.encode(
      payload,
      secret,
      "HS256"
    )
  end

  def self.decode(token)
    payload, = JWT.decode(
      token,
      secret,
      true,
      algorithm: "HS256"
    )

    payload
  rescue JWT::DecodeError
    nil
  end

  def self.secret
    Rails.application.secret_key_base
  end

  private_class_method :secret
end
