# frozen_string_literal: true

module E11y
  module Reliability
    module DLQ
      # Abstract base class for Dead Letter Queue storage backends.
      #
      # Subclass this to implement a custom DLQ backend (file, Redis, database, etc.).
      # All methods raise NotImplementedError by default except replay_batch (which
      # delegates to replay).
      #
      # @see DLQ::FileAdapter for the file-based implementation
      class Base
        # Save a failed event to the DLQ.
        #
        # @param event_data [Hash] Event data
        # @param metadata [Hash] Failure metadata
        # @return [String] event ID
        def save(event_data, metadata: {})
          raise NotImplementedError, "#{self.class}#save is not implemented"
        end

        # List DLQ entries.
        #
        # @param limit [Integer]
        # @param offset [Integer]
        # @param filters [Hash]
        # @return [Array<Hash>]
        def list(limit: 100, offset: 0, filters: {})
          raise NotImplementedError, "#{self.class}#list is not implemented"
        end

        # Return DLQ statistics.
        #
        # @return [Hash]
        def stats
          raise NotImplementedError, "#{self.class}#stats is not implemented"
        end

        # Replay a single event.
        #
        # @param event_id [String]
        # @return [Boolean]
        def replay(event_id)
          raise NotImplementedError, "#{self.class}#replay is not implemented"
        end

        # Replay a batch of events. Delegates to replay for each ID.
        #
        # @param event_ids [Array<String>]
        # @return [Hash] { success_count: Integer, failure_count: Integer }
        def replay_batch(event_ids)
          success_count = 0
          failure_count = 0
          event_ids.each do |id|
            replay(id) ? success_count += 1 : failure_count += 1
          end
          { success_count: success_count, failure_count: failure_count }
        end

        # Delete an entry from the DLQ.
        #
        # @param event_id [String]
        # @return [Boolean]
        def delete(event_id)
          raise NotImplementedError, "#{self.class}#delete is not implemented"
        end
      end
    end
  end
end
