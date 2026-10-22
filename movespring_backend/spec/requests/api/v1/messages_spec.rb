describe "POST /api/v1/chat_rooms/:chat_room_id/messages" do
  let(:headers) { { "Authorization" => "Bearer #{token}" } }

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
    other_company = Company.create!(name: "Other Corp", slug: "other")
    other_challenge = Challenge.create!(
      company: other_company, scoring_rule_version: scoring_rule_version,
      name: "Other Challenge", starts_at: 1.day.from_now,
      ends_at: 10.days.from_now, status: "published"
    )
    other_room = ChatRoom.create!(challenge: other_challenge, name: "Secret Chat")

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