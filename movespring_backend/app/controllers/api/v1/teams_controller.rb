# app/controllers/api/v1/teams_controller.rb
module Api
  module V1
    class TeamsController < ApplicationController
      before_action :require_company_admin!, only: [:create]
      before_action :require_employee!, only: [:mine]
      before_action :set_challenge

      # GET /api/v1/challenges/:challenge_id/teams  (the team leaderboard)
      def index
        unless current_user.company_admin? ||
               %w[published active completed].include?(@challenge.status)
          return render json: { error: "Challenge not found in your company" },
                        status: :not_found
        end

        teams = @challenge.teams.includes(:members).order(:id).to_a
        points_by_team = TeamPoints.call(challenge: @challenge)

entries = teams.map do |team|
  member_count = team.members.size
  points = points_by_team.fetch(team.id, 0)

  {
    team_id: team.id,
    name: team.name,
    member_count: member_count,
    points: points,
    average_points: member_count.zero? ? 0.0 : (points.to_f / member_count).round(1),
    # nil when the challenge has no goal
    goal: TeamGoalProgress.call(challenge: @challenge, points: points)
  }
end

        # Highest points first; ties broken by name so the order is stable
        entries.sort_by! { |e| [-e[:points], e[:name].downcase] }

        # Tied teams share a rank (1, 1, 3), the same way your
        # individual leaderboard does it
        previous_points = nil
        current_rank = 0
        entries.each_with_index do |entry, index|
          if entry[:points] != previous_points
            current_rank = index + 1
            previous_points = entry[:points]
          end
          entry[:rank] = current_rank
        end

        render json: {
          challenge_id: @challenge.id,
          challenge_name: @challenge.name,
          challenge_type: @challenge.challenge_type,
          team_goal_points: @challenge.team_goal_points,
          leaderboard: entries
        }, status: :ok
      end

      # POST /api/v1/challenges/:challenge_id/teams  (admin deals the teams)
      def create
        result = TeamFormationService.call(
          challenge: @challenge,
          team_count: params[:team_count],
          team_size: params[:team_size],
          reshuffle: params[:reshuffle]
        )

        if result[:teams]
          render json: {
            message: "Teams formed successfully",
            teams: result[:teams].map { |team| team_json(team) }
          }, status: :created
        else
          render json: { errors: result[:errors] }, status: :unprocessable_entity
        end
      end

      # GET /api/v1/challenges/:challenge_id/my_team
      def mine
       points = TeamPoints.call(challenge: @challenge).fetch(membership.team_id, 0)

render json: {
  team: team_json(membership.team).merge(
    points: points,
    goal: TeamGoalProgress.call(challenge: @challenge, points: points)
  )
}, status: :ok
      end

      private

      # Adds up each person's award points for this challenge, grouped by team.
      # Same rules as the individual leaderboard: eligible activities that
      # sit fully inside the challenge dates.

      def team_json(team)
        {
          id: team.id,
          name: team.name,
          challenge_id: team.challenge_id,
          members: team.members.order(:name).map { |m| { id: m.id, name: m.name } }
        }
      end

      def set_challenge
        @challenge = current_user.company.challenges.find_by(id: params[:challenge_id])
        return if @challenge

        render json: { error: "Challenge not found in your company" }, status: :not_found
      end

      def require_company_admin!
        return if current_user.company_admin?

        render json: { error: "Only company administrators can form teams" },
               status: :forbidden
      end

      def require_employee!
        return if current_user.employee?

        render json: { error: "Only employees can use this endpoint" }, status: :forbidden
      end
    end
  end
end