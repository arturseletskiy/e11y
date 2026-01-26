# frozen_string_literal: true

class TestJob < ActiveJob::Base
  queue_as :default

  def perform(message)
    Rails.logger.info "TestJob performed: #{message}"
  end
end
