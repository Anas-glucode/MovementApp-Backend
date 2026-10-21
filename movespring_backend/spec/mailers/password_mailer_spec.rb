require "rails_helper"

RSpec.describe PasswordMailer, type: :mailer do
  describe "reset" do
    let(:user) { double(email: "reset@example.com") }
    let(:mail) { PasswordMailer.reset(user, "reset-token") }

    it "renders the headers" do
      expect(mail.subject).to eq("Reset your password")
      expect(mail.to).to eq(["reset@example.com"])
      expect(mail.from).to eq(["from@example.com"])
    end

    it "renders the body" do
      expect(mail.body.encoded).to include(
        "http://localhost:3000/reset-password?token=reset-token"
      )
    end
  end
end
