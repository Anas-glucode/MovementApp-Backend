require "rails_helper"

RSpec.describe ApplicationCable::Connection, type: :channel do
  let(:company) { Company.create!(name: "Glucode", slug: "glucode") }
  let(:user) do
    User.create!(name: "Anas", email: "anas@glucode.com", password: "password123",
                 company: company, role: "employee", status: "active")
  end

  it "connects with a valid token" do
    connect "/cable", params: { token: TokenService.issue(user) }
    expect(connection.current_user).to eq(user)
  end

  it "rejects a missing or invalid token" do
    expect { connect "/cable" }.to have_rejected_connection
    expect { connect "/cable", params: { token: "garbage" } }.to have_rejected_connection
  end

  it "rejects a token issued before the user's password changed" do
    old_token = TokenService.issue(user)
    user.update!(password: "new-password-123")

    expect do
      connect "/cable", params: { token: old_token }
    end.to have_rejected_connection
  end
end
