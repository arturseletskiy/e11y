# frozen_string_literal: true

# features/support/world_extensions.rb
#
# World module mixed into every Cucumber scenario.
# Provides:
#   - Rack::Test HTTP helpers (get, post, last_response, etc.)
#   - memory_adapter   — direct access to E11y::Adapters::InMemory instance
#   - clear_events!    — empties the memory adapter
#   - last_tracked_event(type) — most recent event hash for a given class name
#   - tracked_events(type)     — all events for a given class name
#   - find_event_payload(type) — payload hash of the most recent event

module E11yWorldHelpers
  include Rack::Test::Methods

  # Required by Rack::Test — returns the Rack application under test.
  #
  # @return [Rails application]
  def app
    Rails.application
  end

  # Returns the singleton InMemory adapter registered as :memory.
  #
  # @return [E11y::Adapters::InMemory]
  def memory_adapter
    E11y.config.adapters[:memory]
  end

  # Clears all events from the memory adapter.
  # Called automatically in the Before hook; also available in step definitions.
  #
  # @return [void]
  def clear_events!
    memory_adapter.clear!
  end

  # Returns ALL events of the given class name string.
  #
  # Searches by :event_name key (which the event base class sets to the
  # fully-qualified class name, e.g., "Events::OrderCreated").
  #
  # @param event_type [String] e.g. "Events::OrderCreated"
  # @return [Array<Hash>]
  def tracked_events(event_type)
    memory_adapter.find_events(event_type)
  end

  # Returns the most recently tracked event of the given type.
  #
  # @param event_type [String] e.g. "Events::OrderCreated"
  # @return [Hash, nil]
  def last_tracked_event(event_type)
    tracked_events(event_type).last
  end

  # Returns the payload hash of the most recently tracked event of the given type.
  #
  # @param event_type [String] e.g. "Events::OrderCreated"
  # @return [Hash, nil]
  def find_event_payload(event_type)
    last_tracked_event(event_type)&.dig(:payload)
  end

  # Parses the last HTTP response body as JSON.
  #
  # @return [Hash, Array]
  # @raise [JSON::ParserError] if body is not valid JSON
  def parsed_response
    JSON.parse(last_response.body)
  end
end

World(E11yWorldHelpers)
