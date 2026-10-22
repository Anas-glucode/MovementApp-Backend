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

it "creates and broadcasts a message when speaking" do
  subscribe(chat_room_id: chat_room.id)

  expect {
    perform :speak, body: "Hello"
  }.to change(Message, :count).by(1)
   .and have_broadcasted_to("chat_room_#{chat_room.id}")
end