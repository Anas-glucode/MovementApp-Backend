# Preview all emails at http://localhost:3000/rails/mailers/password_mailer_mailer
class PasswordMailerPreview < ActionMailer::Preview

  # Preview this email at http://localhost:3000/rails/mailers/password_mailer_mailer/reset
  def reset
    user = User.first || raise("Create a user to preview the password reset email")
    PasswordMailer.reset(user, user.password_reset_token)
  end

end
