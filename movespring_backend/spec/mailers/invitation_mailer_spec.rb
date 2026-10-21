require "rails_helper"

RSpec.describe InvitationMailer, type: :mailer do
  describe "invite" do
    let(:invitation) { double(email: "invite@example.com") }
    let(:mail) { InvitationMailer.invite(invitation, "raw-token") }

    it "renders the headers" do
      expect(mail.subject).to eq("Invitation")
      expect(mail.to).to eq(["invite@example.com"])
      expect(mail.from).to eq(["from@example.com"])
    end

    it "renders the body" do
      expect(mail.body.encoded).to include("raw-token")
    end
  end
end
