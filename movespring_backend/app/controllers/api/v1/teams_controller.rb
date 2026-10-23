# app/controllers/api/v1/teams_controller.rb
module Api
  module V1
    class TeamsController < ApplicationController
      before_action :require_company_admin!, only: [:create]
      before_action :require_employee!, only: [:mine]
      before_action :set_challenge

      # GET /api/v1/challenges/:challenge_id/teams  (the team leaderboard)
      def index
        # CHANGED: uses the same list as the challenges controller, so the
        # two can never disagree again. The old hard-coded list was missing
        # "finalizing", which hid the leaderboard from employees after a
        # challenge ended.
        unless current_user.company_admin? ||
               ChallengesController::VISIBLE_TO_EMPLOYEES.include?(@challenge.status)
          return render json: { error: "Challenge not found in your company" },
                        status: :not_found
        end

        render json: {
          challenge_id: @challenge.id,
          challenge_name: @challenge.name,
          challenge_type: @challenge.challenge_type,
          team_goal_points: @challenge.team_goal_points,
          scoring_method: @challenge.team_scoring_method,
          leaderboard: TeamLeaderboard.call(challenge: @challenge)
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
        membership = TeamMembership.includes(:team)
                                   .find_by(challenge_id: @challenge.id,
                                            user_id: current_user.id)

        unless membership
          return render json: { error: "You are not on a team in this challenge" },
                        status: :not_found
        end

        points = TeamPoints.call(challenge: @challenge).fetch(membership.team_id, 0)

        render json: {
          team: team_json(membership.team).merge(
            points: points,
            goal: TeamGoalProgress.call(challenge: @challenge, points: points)
          )
        }, status: :ok
      end

      private

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