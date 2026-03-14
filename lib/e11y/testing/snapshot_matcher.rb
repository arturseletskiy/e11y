# frozen_string_literal: true

require "fileutils"
require "yaml"

module E11y
  module Testing
    # Snapshot matcher for event comparison (ADR-011 F-006).
    #
    # Compares event hashes against YAML snapshots, normalizing volatile fields
    # (timestamp, trace_id, span_id). First run creates the snapshot; subsequent
    # runs compare against it. Use UPDATE_SNAPSHOTS=1 to update snapshots.
    #
    # @example
    #   event = E11y.test_adapter.find_event(Events::OrderCreated)
    #   expect(event).to match_snapshot("order_created_event")
    class SnapshotMatcher
      SNAPSHOTS_DIR = "spec/snapshots/events"
      VOLATILE_KEYS = %i[timestamp trace_id span_id retention_until routed_at].freeze

      def initialize(snapshot_name)
        @snapshot_name = snapshot_name
      end

      def matches?(actual)
        @actual = actual
        @normalized = normalize_event(actual)
        @snapshot_path = File.join(SNAPSHOTS_DIR, "#{@snapshot_name}.yml")

        if update_snapshots? || !File.exist?(@snapshot_path)
          write_snapshot(@normalized)
          true
        else
          @expected = YAML.load_file(@snapshot_path)
          @normalized == @expected
        end
      end

      def failure_message
        if @expected
          "expected event to match snapshot #{@snapshot_name}, but it differed:\n" \
            "Expected:\n#{@expected.to_yaml}\n" \
            "Actual (normalized):\n#{@normalized.to_yaml}"
        else
          "snapshot #{@snapshot_name} not found at #{@snapshot_path}"
        end
      end

      def failure_message_when_negated
        "expected event not to match snapshot #{@snapshot_name}, but it did"
      end

      private

      def normalize_event(event)
        return {} if event.nil?

        event = event.dup
        VOLATILE_KEYS.each { |k| event.delete(k) }
        event.delete(:context) # context contains trace_id, span_id, etc.
        event.delete(:routing)
        deep_stringify(event)
      end

      def deep_stringify(obj)
        case obj
        when Hash
          obj.transform_values { |v| deep_stringify(v) }.transform_keys(&:to_s)
        when Array
          obj.map { |v| deep_stringify(v) }
        else
          obj
        end
      end

      def update_snapshots?
        %w[1 true].include?(ENV.fetch("UPDATE_SNAPSHOTS", nil))
      end

      def write_snapshot(data)
        FileUtils.mkdir_p(File.dirname(@snapshot_path))
        File.write(@snapshot_path, data.to_yaml)
      end
    end
  end
end
