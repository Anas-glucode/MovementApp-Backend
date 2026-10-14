module Api
module V1
class CompaniesController < ApplicationController
      before_action :require_company_admin!, only: [:update]

  def show
    render json: {
      company: company_json(current_user.company)
    }, status: :ok
  end

  def update
    company = current_user.company

    if company.update(company_params)
      render json: {
        message: "Company updated successfully",
        company: company_json(company)
      }, status: :ok
    else
      render json: {
        error: company.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  private

  def require_company_admin!
    return if current_user.company_admin?

    render json: {
      error: "Only company administrators can manage company details"
    }, status: :forbidden
  end

  def company_params
    params.require(:company).permit(:name)
  end

  def company_json(company)
    {
      id: company.id,
      name: company.name,
      slug: company.slug,
      status: company.status
    }
  end
end

end
end