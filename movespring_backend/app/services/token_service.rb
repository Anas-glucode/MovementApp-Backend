class TokenService
  LIFETIME = 30.minutes

  def self.issue(user)
    now = Time.current.to_i

    payload = {
  sub: user.id,
  # Last 10 chars of the bcrypt salt. It changes whenever the password changes
  pwd: user.password_salt.last(10),
  iat: now,
  exp: (Time.current + LIFETIME).to_i
}

    JWT.encode(payload, secret, "HS256")
  end

  def self.decode(token)
    payload, = JWT.decode(token, secret, true, algorithm: "HS256")
    payload
  rescue JWT::DecodeError
    nil
  end

 def self.secret
  # A key made just for JWTs, derived from the app's master secret
  Rails.application.key_generator.generate_key("jwt-signing", 32)
end

  private_class_method :secret
end
