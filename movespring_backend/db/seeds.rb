if Rails.env.development?
  company = Company.find_or_create_by!(slug: "glucode") { |c| c.name = "Glucode" }

  user = User.find_or_initialize_by(email: "anas@glucode.com")
  if user.new_record?
    user.assign_attributes(name: "Anas", password: "password123",
                           company: company, role: "employee", status: "active")
    user.save!
  end

  srv = ScoringRuleVersion.find_or_create_by!(version_number: 1) do |s|
    s.name = "Dev scoring rules"
    s.status = "draft"
    s.rules = {}
  end

  challenge = Challenge.find_or_create_by!(company: company, name: "Dev Challenge") do |c|
    c.scoring_rule_version = srv
    c.starts_at = 1.day.from_now
    c.ends_at = 10.days.from_now
    c.status = "published"
  end
  room = ChatRoom.find_or_create_by!(challenge: challenge) { |r| r.name = "Dev Chat" }

  other_company = Company.find_or_create_by!(slug: "other") { |c| c.name = "Other Corp" }
  other_challenge = Challenge.find_or_create_by!(company: other_company, name: "Other Challenge") do |c|
    c.scoring_rule_version = srv
    c.starts_at = 1.day.from_now
    c.ends_at = 10.days.from_now
    c.status = "published"
  end
  other_room = ChatRoom.find_or_create_by!(challenge: other_challenge) { |r| r.name = "Secret Chat" }

  puts "Login: anas@glucode.com / password123"
  puts "room_id=#{room.id}  other_room_id=#{other_room.id}"
end