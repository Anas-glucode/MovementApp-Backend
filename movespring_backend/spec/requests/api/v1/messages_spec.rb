require 'rails_helper'

RSpec.describe "Api::V1::Messages", type: :request do
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

  let(:token) do
    TokenService.issue(user)
  end

  describe "GET /api/v1/chat_rooms/:chat_room_id/messages" do
    it "returns messages for an authorized company chat room" do
      Message.create!(
        user: user,
        chat_room: chat_room,
        body: "Hello team!"
      )

      get api_v1_chat_room_messages_path(chat_room_id: chat_room.id),
          headers: {
            "Authorization" => "Bearer #{token}"
          }

      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)

      expect(json["chat_room_id"]).to eq(chat_room.id)
      expect(json["messages"].size).to eq(1)
      expect(json["messages"].first["body"]).to eq("Hello team!")
    end

    it "blocks access if the user tries to view a chat from another company" do
      other_company = Company.create!(
        name: "Other Corp",
        slug: "other"
      )

      other_challenge = Challenge.create!(
        company: other_company,
        scoring_rule_version: scoring_rule_version,
        name: "Other Challenge",
        starts_at: 1.day.from_now,
        ends_at: 10.days.from_now,
        status: "published"
      )

      other_room = ChatRoom.create!(
        challenge: other_challenge,
        name: "Secret Chat"
      )

      get api_v1_chat_room_messages_path(chat_room_id: other_room.id),
          headers: {
            "Authorization" => "Bearer #{token}"
          }

      expect(response).to have_http_status(:forbidden)
    end
  end
end