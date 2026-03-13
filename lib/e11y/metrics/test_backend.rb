# frozen_string_literal: true

module E11y
  module Metrics
    # In-memory metrics backend for tests.
    #
    # Records all metric calls so test assertions can verify what was tracked
    # without using mocks on E11y::Metrics directly.
    #
    # @example
    #   backend = E11y::Metrics::TestBackend.new
    #   E11y::Metrics.instance_variable_set(:@backend, backend)
    #
    #   MyService.call
    #
    #   expect(backend.increment_count(:orders_total)).to eq(1)
    #   expect(backend.increments).to include(hash_including(name: :orders_total))
    class TestBackend
      attr_reader :increments, :histograms, :gauges

      def initialize
        reset!
      end

      # @param name [Symbol] Metric name
      # @param labels [Hash] Metric labels
      # @param value [Integer] Increment amount
      def increment(name, labels = {}, value: 1)
        @increments << { name: name, labels: labels, value: value }
      end

      # @param name [Symbol] Metric name
      # @param value [Numeric] Observed value
      # @param labels [Hash] Metric labels
      def histogram(name, value, labels = {}, buckets: nil) # rubocop:todo Lint/UnusedMethodArgument
        @histograms << { name: name, value: value, labels: labels }
      end

      # @param name [Symbol] Metric name
      # @param value [Numeric] Gauge value
      # @param labels [Hash] Metric labels
      def gauge(name, value, labels = {})
        @gauges << { name: name, value: value, labels: labels }
      end

      # Reset all recorded metrics.
      def reset!
        @increments = []
        @histograms = []
        @gauges     = []
      end

      # Count how many times a counter was incremented (any labels).
      #
      # @param name [Symbol] Metric name
      # @return [Integer]
      def increment_count(name)
        @increments.count { |r| r[:name] == name }
      end
    end
  end
end
