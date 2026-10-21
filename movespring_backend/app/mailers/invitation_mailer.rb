class InvitationMailer < ApplicationMailer
  def invite(invitation, token)
    mail(
      to: invitation.email,
      subject: "Invitation",
      body: "Your invitation token is #{token}"
    )
  end
end
