# frozen_string_literal: true

# Test controller for file upload filtering
class DocumentsController < ApplicationController
  def create
    file = params[:document][:file]
    metadata = params[:document][:metadata] || {}

    Events::DocumentUploaded.track(
      filename: file.original_filename,
      size: file.size,
      metadata: metadata.to_unsafe_h
    )

    render json: {
      document_id: SecureRandom.uuid,
      filename: file.original_filename,
      size: file.size,
      uploaded: true
    }, status: :created
  end
end
