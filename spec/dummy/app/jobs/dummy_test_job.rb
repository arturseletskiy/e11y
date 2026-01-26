# frozen_string_literal: true

class DummyTestJob < ActiveJob::Base
  queue_as :default

  def perform(message)
    Rails.logger.info "DummyTestJob performed: #{message}"
  end
end
