# frozen_string_literal: true

require_relative "in_memory"

module E11y
  module Adapters
    # InMemoryTest Adapter — extends InMemory with test-specific helpers.
    #
    # Overrides `last_event` to skip Rails auto-instrumentation events
    # (E11y::Events::Rails::*) that fire after each HTTP request and
    # would otherwise obscure the event your test just tracked.
    #
    # Use this adapter in test suites; use `InMemory` in production configs.
    #
    # @example
    #   let(:adapter) { E11y::Adapters::InMemoryTest.new }
    #   before { E11y.register_adapter :memory, adapter }
    class InMemoryTest < InMemory
      # Return the last event that was NOT fired by Rails auto-instrumentation.
      #
      # @return [Hash, nil]
      def last_event
        events.reverse_each.find do |e|
          !e[:event_name].to_s.start_with?("E11y::Events::Rails::")
        end
      end
    end
  end
end
