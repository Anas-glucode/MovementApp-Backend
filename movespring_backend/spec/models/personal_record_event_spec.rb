require 'rails_helper'

RSpec.describe PersonalRecordEvent, type: :model do
  fixtures :companies, :users, :activities

  let(:user) { users(:one) }
  let(:activity) { activities(:one) }

  let(:valid_attributes) do
    {
      user: user,
      activity: activity,
      record_type: "longest_run",
      previous_value: 4000,
      new_value: 5000,
      achieved_at: Time.current
    }
  end

  describe "validations" do
    it "accepts a valid personal record event" do
      event = described_class.new(valid_attributes)

      expect(event).to be_valid
    end

    it "rejects an unknown record type" do
      event = described_class.new(
        valid_attributes.merge(record_type: "unknown_record")
      )

      expect(event).not_to be_valid
      expect(event.errors[:record_type]).to be_present
    end

    it "rejects a negative new value" do
      event = described_class.new(
        valid_attributes.merge(new_value: -100)
      )

      expect(event).not_to be_valid
      expect(event.errors[:new_value]).to be_present
    end

    it "rejects a negative previous value" do
      event = described_class.new(
        valid_attributes.merge(previous_value: -100)
      )

      expect(event).not_to be_valid
      expect(event.errors[:previous_value]).to be_present
    end

    it "rejects a new value that does not improve the previous record" do
      event = described_class.new(
        valid_attributes.merge(new_value: 4000)
      )

      expect(event).not_to be_valid
      expect(event.errors[:new_value]).to be_present
    end

    it "allows a first personal record without a previous value" do
      event = described_class.new(
        valid_attributes.merge(previous_value: nil)
      )

      expect(event).to be_valid
    end

    it "requires an achievement date" do
      event = described_class.new(
        valid_attributes.merge(achieved_at: nil)
      )

      expect(event).not_to be_valid
      expect(event.errors[:achieved_at]).to be_present
    end

    it "rejects an activity belonging to another user" do
      event = described_class.new(
        valid_attributes.merge(
          user: users(:two),
          activity: activities(:one)
        )
      )

      expect(event).not_to be_valid
      expect(event.errors[:activity]).to be_present
    end
  end
end