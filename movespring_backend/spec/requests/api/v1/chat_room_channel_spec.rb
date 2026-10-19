require 'rails_helper'

RSpec.describe ChatRoomChannel, type: :channel do
  let(:company) { Company.create!(name: "Glucode", slug: "glucode") }
  let(:user) { User.create!(name: "Anas", email: "anas@glucode.com", password: "password123", company: company, role: "employee", status: "active") }
  let(:challenge) { Challenge.create!(company: company, title: "Step Challenge", starts_at: 1.day.from_now, ends_at: 10.days.from_now, status: "published") }
  let(:chat_room) { ChatRoom.create!(challenge: challenge, name: "Step Challenge Chat") }

  before do
    stub_connection current_user: user
  end

  it "successfully subscribes to a valid chat room stream" do
    subscribe(chat_room_id: chat_room.id)
    
    expect(subscription).to be_confirmed
    expect(transmissions).not_include(a_hash_including("type" => "rejected"))
    expect(streams).to include("chat_room_#{chat_room.id}")
  end

  it "rejects subscription for non-existent chat room" do
    subscribe(chat_room_id: 99999)
    
    expect(subscription).to be_rejected
  end
end