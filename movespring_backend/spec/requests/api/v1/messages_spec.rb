require 'rails_helper'

RSpec.describe "Api::V1::Messages", type: :request do
  let(:company) { Company.create!(name: "Glucode", slug: "glucode") }

  let(:user) do
    User.create!(name: "Anas", email: "anas@glucode.com", password: "password123",
                 company: company, role: "employee", status: "active")
  end

  let(:scoring_rule_version) do
    ScoringRuleVersion.create!(
      name: "Test scoring rules",
      version_number: (ScoringRuleVersion.maximum(:version_number) || 0) + 1,
      status: "draft", rules: {}
    )
  end

  let(:challenge) do
    Challenge.create!(company: company, scoring_rule_version: scoring_rule_version,
                      name: "Step Challenge", starts_at: 1.day.from_now,
                      ends_at: 10.days.from_now, status: "published")
  end

  let(:chat_room) { ChatRoom.create!(challenge: challenge, name: "Step Challenge Chat") }
  let(:token) { TokenService.issue(user) }
  let(:headers) { { "Authorization" => "Bearer #{token}" } }

  let(:other_room) do
    other_company = Company.create!(name: "Other Corp", slug: "other")
    other_challenge = Challenge.create!(company: other_company,
                                        scoring_rule_version: scoring_rule_version,
                                        name: "Other Challenge", starts_at: 1.day.from_now,
                                        ends_at: 10.days.from_now, status: "published")
    ChatRoom.create!(challenge: other_challenge, name: "Secret Chat")
  end

  describe "GET /api/v1/chat_rooms/:chat_room_id/messages" do
    it "returns messages for an authorized company chat room" do
      Message.create!(user: user, chat_room: chat_room, body: "Hello team!")

      get api_v1_chat_room_messages_path(chat_room_id: chat_room.id), headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["chat_room_id"]).to eq(chat_room.id)
      expect(json["messages"].size).to eq(1)
      expect(json["messages"].first["body"]).to eq("Hello team!")
    end

    it "returns the newest 50 messages in chronological order" do
      51.times { |i| Message.create!(user: user, chat_room: chat_room, body: "m#{i}") }

      get api_v1_chat_room_messages_path(chat_room_id: chat_room.id), headers: headers

      bodies = JSON.parse(response.body)["messages"].map { |m| m["body"] }
      expect(bodies.size).to eq(50)
      expect(bodies.last).to eq("m50")
      expect(bodies.first).to eq("m1")
    end

    it "blocks access to another company's chat room" do
      get api_v1_chat_room_messages_path(chat_room_id: other_room.id), headers: headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/v1/chat_rooms/:chat_room_id/messages" do
    it "creates a message in your company's chat room" do
      expect {
        post api_v1_chat_room_messages_path(chat_room_id: chat_room.id),
             params: { message: { body: "Hi!" } }, headers: headers
      }.to change(Message, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["message"]["body"]).to eq("Hi!")
    end

    it "broadcasts the new message to the room" do
      expect {
        post api_v1_chat_room_messages_path(chat_room_id: chat_room.id),
             params: { message: { body: "Hi!" } }, headers: headers
      }.to have_broadcasted_to("chat_room_#{chat_room.id}")
    end

    it "rejects a blank body" do
      post api_v1_chat_room_messages_path(chat_room_id: chat_room.id),
           params: { message: { body: "" } }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "forbids posting to another company's room" do
      post api_v1_chat_room_messages_path(chat_room_id: other_room.id),
           params: { message: { body: "Hi" } }, headers: headers
      expect(response).to have_http_status(:forbidden)
      expect(Message.count).to eq(0)
    end

    it "requires authentication" do
      post api_v1_chat_room_messages_path(chat_room_id: chat_room.id),
           params: { message: { body: "Hi" } }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "media and deleting" do
    let(:png_data) do
      Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")
    end
    let(:image) do
      Rack::Test::UploadedFile.new(StringIO.new(png_data), "image/png", original_filename: "pic.png")
    end

    it "sends a message with only an image" do
      post api_v1_chat_room_messages_path(chat_room_id: chat_room.id),
           params: { message: { media: [image] } }, headers: headers

      expect(response).to have_http_status(:created)
      media = JSON.parse(response.body)["message"]["media"]
      expect(media.size).to eq(1)
      expect(media.first["kind"]).to eq("image")
    end

    it "rejects unsupported file types" do
      pdf = Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4 test"), "application/pdf",
                                         original_filename: "a.pdf")
      post api_v1_chat_room_messages_path(chat_room_id: chat_room.id),
           params: { message: { body: "doc", media: [pdf] } }, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "lets the author delete their message" do
      message = Message.create!(user: user, chat_room: chat_room, body: "bye")

      expect {
        delete api_v1_chat_room_message_path(chat_room_id: chat_room.id, id: message.id),
               headers: headers
      }.to change(Message, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end

    it "stops an employee deleting someone else's message" do
      other_user = User.create!(name: "Sam", email: "sam@glucode.com", password: "password123",
                                company: company, role: "employee", status: "active")
      message = Message.create!(user: other_user, chat_room: chat_room, body: "mine")

      delete api_v1_chat_room_message_path(chat_room_id: chat_room.id, id: message.id),
             headers: headers

      expect(response).to have_http_status(:forbidden)
      expect(Message.exists?(message.id)).to be true
    end
  end
end
