module Api
  module V1
    class ChallengesController < ApplicationController
      before_action :require_company_admin!, only: [:create, :update, :publish]
      before_action :require_employee!, only: [:join, :mine]
      before_action :set_challenge, only: [:show, :update, :publish, :join]

      def index
        challenges = current_user.company.challenges
                                  .order(starts_at: :asc, id: :asc)

        unless current_user.company_admin?
          challenges = challenges.where(
            status: %w[published active completed]
          )
        end

        render json: {
          challenges: challenges.map { |challenge| challenge_json(challenge) }
        }, status: :ok
      end

      def mine
        participations = current_user.challenge_participations
                                      .includes(:challenge)
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
               %w[published active completed].include?(@challenge.status)
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
            error: challenge.errors.full_messages
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
            error: challenge.errors.full_messages
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
            error: @challenge.errors.full_messages
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

        if participation.save
          render json: {
            message: "You have joined the challenge successfully",
            participation: {
              id: participation.id,
              challenge_id: participation.challenge_id,
              joined_at: participation.created_at.iso8601
            },
            challenge: challenge_json(@challenge)
          }, status: :created
        else
          render json: {
            error: participation.errors.full_messages
          }, status: :unprocessable_entity
        end
      rescue ActiveRecord::RecordNotUnique
        render json: {
          error: "You have already joined this challenge"
        }, status: :conflict
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
        params.require(:challenge).permit(
          :name,
          :description,
          :starts_at,
          :ends_at
        )
      end

      def challenge_json(challenge)
        {
          id: challenge.id,
          name: challenge.name,
          description: challenge.description,
          starts_at: challenge.starts_at.iso8601,
          ends_at: challenge.ends_at.iso8601,
          status: challenge.status,
          scoring_rule_version: challenge.scoring_rule_version.version_number,
          company_id: challenge.company_id,
          created_at: challenge.created_at.iso8601,
          updated_at: challenge.updated_at.iso8601
        }
      end
    end
  end
end
