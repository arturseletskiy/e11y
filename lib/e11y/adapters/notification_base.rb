# lib/e11y/adapters/notification_base.rb
# frozen_string_literal: true

require_relative "base"
require_relative "../notifications/throttleable"

module E11y
  module Adapters
    # Abstract base class for human-facing notification adapters.
    #
    # Subclasses deliver events to messaging and email channels. Unlike logging
    # adapters (Loki, File), notification adapters are intended for human consumption
    # and therefore include throttling and digest logic via Throttleable.
    #
    # Subclasses MUST implement:
    #   - #adapter_id_source → String  (stable identifier for store key scoping)
    #   - #deliver_alert(event_data) → Boolean
    #   - #deliver_digest(events:, window_start:, window_end:, total_count:, truncated:, truncated_count:) → Boolean
    #
    # @see E11y::Adapters::MattermostAdapter
    # @see E11y::Adapters::ActionMailerAdapter
    class NotificationBase < Base
      include Notifications::Throttleable

      # @param config [Hash]
      # @option config [E11y::Store::Base] :store (required) Shared state backend
      # @option config [Integer] :max_event_types (20) Max unique event types in one digest
      def initialize(config = {})
        @store = config[:store] or raise ArgumentError,
                                         "#{self.class.name} requires :store — " \
                                         "use E11y::Store::Memory (single-process) or " \
                                         "E11y::Store::RailsCache (multi-process)"
        @max_event_types = config.fetch(:max_event_types, 20)
        super
      end

      def capabilities
        super.merge(batching: false, compression: false, async: false, streaming: false)
      end

      private

      def validate_config!
        # store presence already validated in initialize before super
      end
    end
  end
end
