# frozen_string_literal: true

module E11y
  module Testing
    # RSpec matchers for event tracking assertions (ADR-011 F-002)
    #
    # @example
    #   expect { OrdersController.create }.to have_tracked_event(Events::OrderCreated)
    #   expect { action }.to have_tracked_event(Events::OrderPaid).with(order_id: 123)
    #   expect { action }.to have_tracked_event(Events::OrderPaid).once
    module RSpecMatchers
      # rubocop:disable Naming/PredicatePrefix -- RSpec matcher convention: have_tracked_event
      def have_tracked_event(event_class_or_pattern)
        HaveTrackedEventMatcher.new(event_class_or_pattern)
      end
      # rubocop:enable Naming/PredicatePrefix

      alias track_event have_tracked_event
    end
  end
end
