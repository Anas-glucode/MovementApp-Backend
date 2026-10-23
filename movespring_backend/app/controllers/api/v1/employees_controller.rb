
module Api
  module V1
    class EmployeesController < ApplicationController
      before_action :require_company_admin!, only: [
        :index,
        :update,
        :deactivate,
        :reactivate,
        :change_role
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
            errors: employee.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

     def deactivate
  employee = find_company_employee
  return unless employee

  result = nil
  # Lock the company row so two admins can't deactivate each other at once
  current_user.company.with_lock do
    if last_active_admin?(employee)
      result = :last_admin
    else
      result = employee.update(status: "inactive") ? :ok : :invalid
    end
  end

  case result
  when :ok
    render json: { message: "Employee deactivated successfully", employee: employee_json(employee) }, status: :ok
  when :last_admin
    render json: { error: "The last active company administrator cannot be deactivated" }, status: :unprocessable_entity
  else
    render json: { errors: employee.errors.full_messages }, status: :unprocessable_entity
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
      errors: employee.errors.full_messages
    }, status: :unprocessable_entity
  end
end

      def change_role
        employee = find_company_employee
        return unless employee

        new_role = params[:role].to_s
        unless User.roles.key?(new_role)
          return render json: { error: "Invalid role" },
                        status: :unprocessable_entity
        end

        result = nil
        current_user.company.with_lock do
          if employee.company_admin? && new_role == "employee" &&
             last_active_admin?(employee)
            result = :last_admin
          else
            result = employee.update(role: new_role) ? :ok : :invalid
          end
        end

        case result
        when :ok
          render json: {
            message: "Role updated",
            employee: employee_json(employee)
          }, status: :ok
        when :last_admin
          render json: {
            error: "The last active company administrator cannot be demoted"
          }, status: :unprocessable_entity
        else
          render json: {
            errors: employee.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      private

      def last_active_admin?(employee)
  # Only matters for people who are currently an active admin.
  # An inactive admin or a regular employee can never be "the last one".
  return false unless employee.company_admin? && employee.active?

  # Look for any OTHER active admin in this company.
  # If there are none, this person is the last one.
  current_user.company.users
              .company_admin
              .active
              .where.not(id: employee.id)
              .none?
end

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
