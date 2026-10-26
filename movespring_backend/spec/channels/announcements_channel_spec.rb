require "rails_helper"

RSpec.describe AnnouncementsChannel, type: :channel do
  let(:company) { Company.create!(name: "Channel Company", slug: "channel-company") }
  let(:user) do
    User.create!(
      name: "Channel User",
      email: "channel-user@example.com",
      password: "Password123!",
      company: company,
      role: "employee",
      status: "active"
    )
  end

  before do
    stub_connection current_user: user
  end

  it "streams company announcements for the connected user's company" do
    subscribe(company_id: 999_999)

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("announcements_company_#{company.id}")
  end

  it "rejects a user whose account has been deactivated" do
    user.update!(status: "inactive")
    subscribe

    expect(subscription).to be_rejected
  end
end
