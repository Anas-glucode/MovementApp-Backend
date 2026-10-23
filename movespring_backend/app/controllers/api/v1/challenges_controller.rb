module Api
  module V1
    class ChallengesController < ApplicationController
      # What employees are allowed to see. "finalizing" is included so a
      # challenge doesn't vanish from the app the moment it ends.
      VISIBLE_TO_EMPLOYEES = %w[published active finalizing completed].freeze

      before_action :require_company_admin!, only: [:create, :update, :publish, :finalize, :cancel]
      before_action :require_employee!, only: [:join, :mine]
      before_action :set_challenge, only: [:show, :update, :publish, :join, :finalize, :cancel, :leaderboard]

      def index
        # includes(:scoring_rule_version): challenge_json reads it for every
        # challenge, so load them all at once instead of one query each.
        challenges = current_user.company.challenges
                                 .includes(:scoring_rule_version)
                                 .order(starts_at: :asc, id: :asc)

        unless current_user.company_admin?
          challenges = challenges.where(status: VISIBLE_TO_EMPLOYEES)
        end

        render json: {
          challenges: challenges.map { |challenge| challenge_json(challenge) }
        }, status: :ok
      end

      def mine
        participations = current_user.challenge_participations
                                     .includes(challenge: :scoring_rule_version)
                                     .order(created_at: :desc)

        render json: {
          challenges: participations.map do |participation|
            challenge_json(participation.challenge)
          end
        }, status: :ok
      end

      def show
        return unless @challenge

        unless current_user.company_admin? ||
               VISIBLE_TO_EMPLOYEES.include?(@challenge.status)
          return render json: {
            error: "Challenge not found in your company"
          }, status: :not_found
        end

        render json: {
          challenge: challenge_json(@challenge)
        }, status: :ok
      end

      def create
        scoring_rule_version = ScoringRuleVersion
                               .where(status: "published")
                               .order(version_number: :desc)
                               .first

        unless scoring_rule_version
          return render json: {
            error: "No published scoring rules are available"
          }, status: :unprocessable_entity
        end

        challenge = current_user.company.challenges.new(challenge_params)
        challenge.scoring_rule_version = scoring_rule_version

        if challenge.save
          render json: {
            message: "Challenge created successfully",
            challenge: challenge_json(challenge)
          }, status: :created
        else
          render json: {
            errors: challenge.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      def update
        return unless @challenge

        unless @challenge.status == "draft"
          return render json: {
            error: "Only draft challenges can be edited"
          }, status: :unprocessable_entity
        end

        if @challenge.update(challenge_params)
          render json: {
            message: "Challenge updated successfully",
            challenge: challenge_json(@challenge)
          }, status: :ok
        else
          render json: {
            errors: @challenge.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      def publish
        return unless @challenge

        unless @challenge.status == "draft"
          return render json: {
            error: "Only draft challenges can be published"
          }, status: :unprocessable_entity
        end

        if @challenge.starts_at <= Time.current
          return render json: {
            error: "The challenge start time must be in the future to publish"
          }, status: :unprocessable_entity
        end

        if @challenge.update(status: "published")
          render json: {
            message: "Challenge published successfully",
            challenge: challenge_json(@challenge)
          }, status: :ok
        else
          render json: {
            errors: @challenge.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # PATCH /api/v1/challenges/:id/cancel
      # Calls a challenge off before it ends.
      def cancel
        return unless @challenge

        unless %w[draft published active].include?(@challenge.status)
          return render json: {
            error: "Only draft, published or active challenges can be cancelled"
          }, status: :unprocessable_entity
        end

        if @challenge.update(status: "cancelled")
          render json: {
            message: "Challenge cancelled",
            challenge: challenge_json(@challenge)
          }, status: :ok
        else
          render json: {
            errors: @challenge.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # PATCH /api/v1/challenges/:id/finalize
      # Locks the final results. Only possible once the challenge has ended
      # (status "finalizing") and every activity from it has been reviewed,
      # because after this no more points can be added.
      def finalize
        return unless @challenge

        unless @challenge.status == "finalizing"
          return render json: {
            error: "Only a challenge that has ended and is finalizing can be finalised"
          }, status: :unprocessable_entity
        end

        waiting = @challenge.unreviewed_activities.count

        if waiting.positive?
          return render json: {
            error: "#{waiting} activities are still waiting for review. " \
                   "Review them before finalising.",
            pending_review_count: waiting
          }, status: :unprocessable_entity
        end

        if @challenge.update(status: "completed", finalized_at: Time.current)
          render json: {
            message: "Challenge finalised. Results are now locked.",
            challenge: challenge_json(@challenge)
          }, status: :ok
        else
          render json: {
            errors: @challenge.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      def join
        return unless @challenge

        if @challenge.status != "published" ||
           @challenge.starts_at <= Time.current
          return render json: {
            error: "This challenge is not open for joining"
          }, status: :unprocessable_entity
        end

        if current_user.challenge_participations.exists?(
          challenge_id: @challenge.id
        )
          return render json: {
            error: "You have already joined this challenge"
          }, status: :conflict
        end

        participation = current_user.challenge_participations.new(
          challenge: @challenge
        )
        team = nil

        # One all-or-nothing step: joining and landing on a team succeed together.
        # If the team step raises, the join is rolled back as well.
        ChallengeParticipation.transaction do
          if participation.save
            team = TeamAssignmentService.call(challenge: @challenge, user: current_user)
          end
        end

        if participation.persisted?
          render json: {
            message: "You have joined the challenge successfully",
            participation: {
              id: participation.id,
              challenge_id: participation.challenge_id,
              joined_at: participation.created_at.iso8601
            },
            # null when it's an individual challenge or teams aren't formed yet
            team: team && { id: team.id, name: team.name },
            challenge: challenge_json(@challenge)
          }, status: :created
        else
          render json: {
            errors: participation.errors.full_messages
          }, status: :unprocessable_entity
        end
      rescue ActiveRecord::RecordNotUnique
        render json: {
          error: "You have already joined this challenge"
        }, status: :conflict
      rescue ActiveRecord::RecordInvalid => e
        render json: {
          errors: e.record.errors.full_messages
        }, status: :unprocessable_entity
      end

      def leaderboard
        return unless @challenge

        unless current_user.company_admin? ||
               VISIBLE_TO_EMPLOYEES.include?(@challenge.status)
          return render json: {
            error: "Challenge not found in your company"
          }, status: :not_found
        end

        participations = @challenge.challenge_participations.includes(:user).to_a
        user_ids = participations.map(&:user_id)

        points_by_user = if user_ids.empty?
                           {}
                         else
                           ChallengeActivityAward
                             .joins(:activity)
                             .where(
                               challenge_id: @challenge.id,
                               scoring_rule_version_id: @challenge.scoring_rule_version_id
                             )
                             .where(
                               activities: {
                                 user_id: user_ids,
                                 status: "eligible"
                               }
                             )
                             .where(
                               "activities.started_at >= ? AND activities.ended_at <= ?",
                               @challenge.starts_at,
                               @challenge.ends_at
                             )
                             .group("activities.user_id")
                             .sum(:points)
                         end

        entries = participations.map do |participation|
          {
            user_id: participation.user.id,
            name: participation.user.name,
            points: points_by_user.fetch(participation.user_id, 0)
          }
        end

        entries.sort_by! { |entry| [-entry[:points], entry[:name].downcase] }

        # Ties share a rank (1, 1, 3), like a race with a dead heat.
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
          scoring_rule_version: @challenge.scoring_rule_version.version_number,
          leaderboard: entries
        }, status: :ok
      end

      private

      def set_challenge
        @challenge = current_user.company.challenges.find_by(id: params[:id])

        return if @challenge

        render json: {
          error: "Challenge not found in your company"
        }, status: :not_found
      end

      def require_company_admin!
        return if current_user.company_admin?

        render json: {
          error: "Only company administrators can manage challenges"
        }, status: :forbidden
      end

      def require_employee!
        return if current_user.employee?

        render json: {
          error: "Only employees can use this endpoint"
        }, status: :forbidden
      end

      def challenge_params
        params.require(:challenge).permit(:name, :description, :starts_at, :ends_at, :challenge_type, :team_goal_points)
      end

      def challenge_json(challenge)
        {
          id: challenge.id,
          name: challenge.name,
          description: challenge.description,
          starts_at: challenge.starts_at.iso8601,
          ends_at: challenge.ends_at.iso8601,
          status: challenge.status,
          challenge_type: challenge.challenge_type,
          scoring_rule_version: challenge.scoring_rule_version.version_number,
          company_id: challenge.company_id,
          finalized_at: challenge.finalized_at&.iso8601,
          created_at: challenge.created_at.iso8601,
          updated_at: challenge.updated_at.iso8601
        }
      end
    end
  end
end