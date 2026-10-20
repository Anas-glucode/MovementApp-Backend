require 'rails_helper'

RSpec.describe ChatRoomChannel, type: :channel do
  let(:company) do
    Company.create!(
      name: "Glucode",
      slug: "glucode"
    )
  end

  let(:user) do
    User.create!(
      name: "Anas",
      email: "anas@glucode.com",
      password: "password123",
      company: company,
      role: "employee",
      status: "active"
    )
  end

  let(:scoring_rule_version) do
    ScoringRuleVersion.create!(
      name: "Test scoring rules",
      version_number: (ScoringRuleVersion.maximum(:version_number) || 0) + 1,
      status: "draft",
      rules: {}
    )
  end

  let(:challenge) do
    Challenge.create!(
      company: company,
      scoring_rule_version: scoring_rule_version,
      name: "Step Challenge",
      starts_at: 1.day.from_now,
      ends_at: 10.days.from_now,
      status: "published"
    )
  end

  let(:chat_room) do
    ChatRoom.create!(
      challenge: challenge,
      name: "Step Challenge Chat"
    )
  end

  before do
    stub_connection current_user: user
  end

  it "successfully subscribes to a valid chat room stream" do
    subscribe(chat_room_id: chat_room.id)

    expect(subscription).to be_confirmed
    expect(subscription.instance_variable_get(:@_streams)).to include("chat_room_#{chat_room.id}")
  end

  it "rejects subscription for a non-existent chat room" do
    subscribe(chat_room_id: 99999)

    expect(subscription).to be_rejected
  end
end