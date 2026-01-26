# frozen_string_literal: true

# Load the Rails application
require_relative "application"

# Initialize the Rails application (only if not already initialized)
Rails.application.initialize! unless Rails.application.initialized?
