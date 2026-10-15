Badge.find_or_create_by!(name: "First Step") do |b|
  b.description = "Record your very first activity on MoveSpring!"
  b.category = "milestone"
  b.criteria_type = "single_activity"
  b.criteria_value = 1
  b.icon_url = "/images/badges/first_step.png"
end

Badge.find_or_create_by!(name: "10,000 Step Day") do |b|
  b.description = "Reach 10,000 steps in a single activity."
  b.category = "steps"
  b.criteria_type = "single_activity"
  b.criteria_value = 10000
  b.icon_url = "/images/badges/10k_steps.png"
end

Badge.find_or_create_by!(name: "Endurance Runner") do |b|
  b.description = "Complete an activity with a duration of 30 minutes or more."
  b.category = "duration"
  b.criteria_type = "single_activity"
  b.criteria_value = 1800
  b.icon_url = "/images/badges/endurance.png"
end