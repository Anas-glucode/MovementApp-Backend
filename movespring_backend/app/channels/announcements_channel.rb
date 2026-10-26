class AnnouncementsChannel < ApplicationCable::Channel
  def subscribed
    return reject unless current_user&.active? && current_user.company&.active?

    stream_from "announcements_company_#{current_user.company_id}"
  end
end
