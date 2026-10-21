require 'rails_helper'

RSpec.describe "Api::V1::PasswordResets", type: :request do
  describe "GET /create" do
    it "returns http success" do
      get "/api/v1/password_resets/create"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /update" do
    it "returns http success" do
      get "/api/v1/password_resets/update"
      expect(response).to have_http_status(:success)
    end
  end

end
