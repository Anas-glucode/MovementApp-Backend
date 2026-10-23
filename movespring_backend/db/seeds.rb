if Rails.env.development?
  # Reuse the dev user's existing company so chat rooms land in the company you log in with.
  user = User.find_by(email: "anas@glucode.com")
  company = user&.company || Company.find_or_create_by!(slug: "glucode") { |c| c.name = "Glucode" }

  user ||= User.create!(name: "Anas", email: "anas@glucode.com", password: "password123",
                        company: company, role: "employee", status: "active")

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

  # A room in a different company, used to test that cross-company access is blocked.
  other_company = Company.find_or_create_by!(slug: "other") { |c| c.name = "Other Corp" }
  other_challenge = Challenge.find_or_create_by!(company: other_company, name: "Other Challenge") do |c|
    c.scoring_rule_version = srv
    c.starts_at = 1.day.from_now
    c.ends_at = 10.days.from_now
    c.status = "published"
  end
  other_room = ChatRoom.find_or_create_by!(challenge: other_challenge) { |r| r.name = "Secret Chat" }

  puts "Login: #{user.email} / password123 (company: #{company.name})"
  puts "room_id=#{room.id}  other_room_id=#{other_room.id}"
end