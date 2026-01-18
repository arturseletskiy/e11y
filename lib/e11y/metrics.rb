# frozen_string_literal: true

module E11y
  # Metrics module for auto-creating Yabeda metrics from events.
  #
  # Provides pattern-based metric creation with cardinality protection.
  #
  # @example Configuration
  #   E11y.configure do |config|
  #     config.metrics do
  #       counter_for pattern: 'order.*',
  #                   name: 'orders.total',
  #                   tags: [:status, :currency]
  #
  #       histogram_for pattern: 'order.paid',
  #                     name: 'orders.amount',
  #                     value: ->(e) { e.payload[:amount] },
  #                     tags: [:currency],
  #                     buckets: [10, 50, 100, 500, 1000]
  #     end
  #   end
  module Metrics
    # Metrics module is autoloaded by Zeitwerk
  end
end
