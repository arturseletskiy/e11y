# frozen_string_literal: true

module E11y
  module Testing
    # RSpec matcher for asserting that an event was tracked during block execution.
    #
    # @example Basic usage
    #   expect { OrdersController.create }.to have_tracked_event(Events::OrderCreated)
    #
    # @example With payload
    #   expect { action }.to have_tracked_event(Events::OrderPaid).with(order_id: 123)
    #
    # @example With count
    #   expect { action }.to have_tracked_event(Events::OrderPaid).once
    # rubocop:disable Metrics/ClassLength
    class HaveTrackedEventMatcher
      def initialize(event_class_or_pattern)
        @event_class_or_pattern = event_class_or_pattern
        @payload_matchers = {}
        @severity_matcher = nil
        @count_matcher = nil
        @trace_id_matcher = nil
      end

      def with(payload_hash)
        @payload_matchers = payload_hash
        self
      end

      def with_severity(severity)
        @severity_matcher = severity
        self
      end

      def exactly(count)
        @count_matcher = count
        self
      end

      def at_least(count)
        @count_matcher = [:at_least, count]
        self
      end

      def at_most(count)
        @count_matcher = [:at_most, count]
        self
      end

      def once
        exactly(1)
      end

      def twice
        exactly(2)
      end

      def with_trace_id(trace_id)
        @trace_id_matcher = trace_id
        self
      end

      def matches?(actual = nil)
        actual.call if actual.respond_to?(:call) # Execute block before checking events
        @events = find_matching_events
        return false if @events.empty?
        return false unless count_matches?
        return false unless payload_matches?
        return false unless severity_matches?
        return false unless trace_id_matches?

        true
      end

      def failure_message
        if @events.empty?
          no_events_message
        elsif !count_matches?
          count_mismatch_message
        elsif !payload_matches?
          payload_mismatch_message
        elsif !severity_matches?
          severity_mismatch_message
        else
          trace_id_mismatch_message
        end
      end

      def failure_message_when_negated
        "expected not to have tracked #{event_name}, but it was tracked"
      end

      def supports_block_expectations?
        true
      end

      private

      def find_matching_events
        adapter = E11y.test_adapter
        return [] unless adapter

        adapter.find_events(@event_class_or_pattern)
      end

      def event_name
        case @event_class_or_pattern
        when Class
          @event_class_or_pattern.name
        else
          @event_class_or_pattern.to_s
        end
      end

      def count_matches?
        return true unless @count_matcher

        case @count_matcher
        when Integer
          @events.size == @count_matcher
        when Array
          operator, expected = @count_matcher
          case operator
          when :at_least then @events.size >= expected
          when :at_most then @events.size <= expected
          else false
          end
        end
      end

      def payload_matches?
        return true if @payload_matchers.empty?

        @events.any? do |event|
          payload = event[:payload] || {}
          @payload_matchers.all? do |key, expected_value|
            actual_value = payload[key.to_s] || payload[key.to_sym]
            actual_value == expected_value
          end
        end
      end

      def severity_matches?
        return true unless @severity_matcher

        @events.any? { |event| event[:severity].to_s == @severity_matcher.to_s }
      end

      def trace_id_matches?
        return true unless @trace_id_matcher

        @events.any? { |event| event[:trace_id] == @trace_id_matcher }
      end

      def no_events_message
        adapter = E11y.test_adapter
        if !adapter || adapter.events.empty?
          "expected to have tracked #{event_name}, but no events were tracked at all"
        else
          tracked = adapter.events.map { |e| e[:event_name] }.uniq.join(", ")
          "expected to have tracked #{event_name}, but only tracked: #{tracked}"
        end
      end

      def count_mismatch_message
        expected = case @count_matcher
                   when Integer then "exactly #{@count_matcher}"
                   when Array then "#{@count_matcher[0].to_s.tr('_', ' ')} #{@count_matcher[1]}"
                   end
        "expected to track #{event_name} #{expected} times, but tracked #{@events.size} times"
      end

      def payload_mismatch_message
        "expected #{event_name} with payload #{@payload_matchers.inspect}, " \
          "but got:\n#{@events.map { |e| "  #{e[:payload].inspect}" }.join("\n")}"
      end

      def severity_mismatch_message
        severities = @events.map { |e| e[:severity] }.uniq.join(", ")
        "expected #{event_name} with severity :#{@severity_matcher}, but got: #{severities}"
      end

      def trace_id_mismatch_message
        trace_ids = @events.map { |e| e[:trace_id] }.uniq.join(", ")
        "expected #{event_name} with trace_id #{@trace_id_matcher}, but got: #{trace_ids}"
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
