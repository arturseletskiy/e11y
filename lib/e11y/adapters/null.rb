# frozen_string_literal: true

module E11y
  module Adapters
    # Null Adapter — silently discards all events.
    #
    # Designed for use in tests and development environments where you want
    # to suppress all output while still being able to assert that events
    # were tracked (via the `events` reader).
    #
    # @example In tests
    #   RSpec.configure do |config|
    #     config.before do
    #       E11y.configure do |c|
    #         c.adapters[:null] = E11y::Adapters::NullAdapter.new
    #       end
    #     end
    #   end
    #
    # @example Asserting events
    #   null_adapter = E11y::Adapters::NullAdapter.new
    #   E11y.configure { |c| c.adapters[:null] = null_adapter }
    #
    #   Events::OrderPaid.track(order_id: "123", amount: 99.99)
    #
    #   expect(null_adapter.events.size).to eq(1)
    #   expect(null_adapter.events.last[:event_name]).to eq("order.paid")
    class Null < Base
      attr_reader :events

      def initialize(config = {})
        super
        @events = []
        @mutex = Mutex.new
      end

      # Accept event and store for later inspection. Never raises.
      #
      # @param event_data [Hash] Event payload
      # @return [Boolean] always true
      def write(event_data)
        @mutex.synchronize { @events << event_data.dup }
        true
      end

      # Accept batch and store for later inspection. Never raises.
      #
      # @param events [Array<Hash>] Event payloads
      # @return [Boolean] always true
      def write_batch(events)
        @mutex.synchronize { @events.concat(events.map(&:dup)) }
        true
      end

      # Clear all stored events (useful between test examples).
      #
      # @return [void]
      def clear!
        @mutex.synchronize { @events.clear }
      end

      # @return [Boolean] always true — null adapter is always healthy
      def healthy?
        true
      end

      # @return [Hash] Adapter capabilities
      def capabilities
        { batching: true, compression: false, async: false, streaming: false }
      end
    end

    # Convenience alias matching Quick Start documentation.
    NullAdapter = Null
  end
end
