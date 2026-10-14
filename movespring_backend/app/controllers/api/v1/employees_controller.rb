
module Api
  module V1
    class EmployeesController < ApplicationController
     before_action :require_company_admin!, only: [
  :index,
  :update,
  :deactivate,
  :reactivate
]

      def index
        employees = current_user.company.users.order(:name)

        render json: {
          employees: employees.map { |employee| employee_json(employee) }
        }, status: :ok
      end

      def update
        employee = find_company_employee
        return unless employee

        if employee.update(employee_params)
          render json: {
            message: "Employee updated successfully",
            employee: employee_json(employee)
          }, status: :ok
        else
          render json: {
            error: employee.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

     def deactivate
  employee = find_company_employee
  return unless employee

  if employee.company_admin?
    active_admin_count = current_user.company.users
                                     .company_admin
                                     .active
                                     .count

    if active_admin_count <= 1
      return render json: {
        error: "The last active company administrator cannot be deactivated"
      }, status: :unprocessable_entity
    end
  end

  if employee.update(status: "inactive")
    render json: {
      message: "Employee deactivated successfully",
      employee: employee_json(employee)
    }, status: :ok
  else
    render json: {
      error: employee.errors.full_messages
    }, status: :unprocessable_entity
  end
end

def reactivate
  employee = find_company_employee
  return unless employee

  if employee.update(status: "active")
    render json: {
      message: "Employee reactivated successfully",
      employee: employee_json(employee)
    }, status: :ok
  else
    render json: {
      error: employee.errors.full_messages
    }, status: :unprocessable_entity
  end
end

      private

      def require_company_admin!
        return if current_user.company_admin?

        render json: {
          error: "Only company administrators can manage employees"
        }, status: :forbidden
      end

      def find_company_employee
        employee = current_user.company.users.find_by(id: params[:id])
        return employee if employee

        render json: {
          error: "Employee not found in your company"
        }, status: :not_found

        nil
      end

      def employee_params
        params.require(:employee).permit(:name, :email)
      end

      def employee_json(employee)
        {
          id: employee.id,
          name: employee.name,
          email: employee.email,
          role: employee.role,
          status: employee.status,
          company_id: employee.company_id
        }
      end
    end
  end
end
