require 'rails_helper'

RSpec.describe ChatRoomChannel, type: :channel do
  let(:company) { Company.create!(name: "Glucode", slug: "glucode") }

  let(:user) do
    User.create!(
      name: "Anas", email: "anas@glucode.com", password: "password123",
      company: company, role: "employee", status: "active"
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
      company: company, scoring_rule_version: scoring_rule_version,
      name: "Step Challenge", starts_at: 1.day.from_now,
      ends_at: 10.days.from_now, status: "published"
    )
  end

  let(:chat_room) { ChatRoom.create!(challenge: challenge, name: "Step Challenge Chat") }

  before do
    stub_connection current_user: user
  end

  it "successfully subscribes to a valid chat room stream" do
    subscribe(chat_room_id: chat_room.id)

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("chat_room_#{chat_room.id}")
  end

  it "rejects subscription for a non-existent chat room" do
    subscribe(chat_room_id: 99999)

    expect(subscription).to be_rejected
  end

  it "rejects subscription to another company's chat room" do
    other_company = Company.create!(name: "Other Corp", slug: "other")
    other_challenge = Challenge.create!(
      company: other_company, scoring_rule_version: scoring_rule_version,
      name: "Other Challenge", starts_at: 1.day.from_now,
      ends_at: 10.days.from_now, status: "published"
    )
    other_room = ChatRoom.create!(challenge: other_challenge, name: "Secret Chat")

    subscribe(chat_room_id: other_room.id)

    expect(subscription).to be_rejected
  end

  it "creates a message when speaking" do
    subscribe(chat_room_id: chat_room.id)

    expect {
      perform :speak, body: "Hello"
    }.to change(Message, :count).by(1)
  end

  it "broadcasts a message when speaking" do
    subscribe(chat_room_id: chat_room.id)

    expect {
      perform :speak, body: "Hello"
    }.to have_broadcasted_to("chat_room_#{chat_room.id}")
  end
end
