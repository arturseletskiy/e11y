# frozen_string_literal: true

# Test controller for free-text pattern filtering
class ReportsController < ApplicationController
  def create
    report_params = params[:report]&.to_unsafe_h || {}

    Events::ReportCreated.track(**report_params)

    render json: { report_id: SecureRandom.uuid, status: "created" }, status: :created
  end
end
