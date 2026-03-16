# frozen_string_literal: true

require "securerandom"

module E11y
  module Tracing
    # W3C Trace Context propagator.
    #
    # Builds, injects, and parses W3C traceparent headers.
    # Format: {version}-{trace-id}-{parent-id}-{flags}
    # Example: 00-0af7651916cd43dd8448eb211c80319c-00f067aa0ba902b7-01
    #
    # @see https://www.w3.org/TR/trace-context/
    # @see UC-009 Multi-Service Tracing
    class Propagator
      TRACEPARENT_VERSION = "00"
      SAMPLED_FLAG = "01"
      TRACEPARENT_HEADER = "traceparent"
      TRACESTATE_HEADER = "tracestate"

      # Build a W3C traceparent header value from the current trace context.
      #
      # Falls back to E11y::Current if explicit ids are not provided.
      # Generates a random span_id if none is set.
      # Returns nil when no trace_id is available.
      #
      # @param trace_id [String, nil] Override trace_id (optional)
      # @param span_id  [String, nil] Override span_id (optional)
      # @return [String, nil] e.g. "00-abc...32hex-def...16hex-01", or nil
      def self.build_traceparent(trace_id: nil, span_id: nil)
        t_id = trace_id || E11y::Current.trace_id
        return nil if t_id.nil? || t_id.empty?

        s_id = span_id || E11y::Current.span_id
        s_id = SecureRandom.hex(8) if s_id.nil? || s_id.empty?

        sampled = E11y::Current.respond_to?(:sampled) ? E11y::Current.sampled : true
        flags = (sampled != false) ? SAMPLED_FLAG : "00"
        "#{TRACEPARENT_VERSION}-#{t_id}-#{s_id}-#{flags}"
      end

      # Inject W3C trace context headers into a plain Hash of headers.
      #
      # Mutates +headers+ in place and returns it.
      # Does NOT override an existing traceparent entry.
      # Adds tracestate when E11y::Current.baggage is present (F-014).
      #
      # @param headers  [Hash]        Headers hash to mutate
      # @param trace_id [String, nil] Override trace_id (optional)
      # @param span_id  [String, nil] Override span_id (optional)
      # @return [Hash] The (possibly mutated) headers hash
      def self.inject(headers, trace_id: nil, span_id: nil)
        unless headers[TRACEPARENT_HEADER]
          header_value = build_traceparent(trace_id: trace_id, span_id: span_id)
          headers[TRACEPARENT_HEADER] = header_value if header_value
        end

        if !headers[TRACESTATE_HEADER] && E11y::Current.respond_to?(:baggage) && E11y::Current.baggage&.any?
          filtered = filter_baggage_for_propagation(E11y::Current.baggage)
          headers[TRACESTATE_HEADER] = build_tracestate(filtered) if filtered.any?
        end

        headers
      end

      # Parse W3C tracestate header to Hash (key=value pairs).
      # @param tracestate [String, nil] Raw header value
      # @return [Hash] String keys and values (empty hash if invalid)
      def self.parse_tracestate(tracestate)
        return {} unless tracestate.is_a?(String)

        tracestate.split(",").each_with_object({}) do |entry, hash|
          key, value = entry.split("=", 2)
          hash[key.strip] = value.to_s.strip if key && !key.strip.empty?
        end
      end

      # Build W3C tracestate header from baggage Hash.
      # @param baggage_hash [Hash] String keys and values
      # @return [String] e.g. "key1=value1,key2=value2"
      def self.build_tracestate(baggage_hash)
        return "" unless baggage_hash.is_a?(Hash) && baggage_hash.any?

        baggage_hash.map { |k, v| "#{k.to_s}=#{v.to_s}" }.join(",")
      end

      # Filter baggage to allowed keys only (ADR-006 §5.5, PII protection).
      def self.filter_baggage_for_propagation(baggage_hash)
        cfg = E11y.config
        return baggage_hash if cfg.nil?

        cfg.filter_baggage_for_propagation(baggage_hash)
      end

      # Parse a W3C traceparent header string.
      #
      # @param traceparent [String, nil] Raw header value
      # @return [Hash, nil] +{ trace_id:, parent_span_id:, sampled: }+ or nil if invalid
      def self.parse(traceparent)
        return nil unless traceparent.is_a?(String)

        parts = traceparent.split("-")
        return nil unless parts.size == 4

        _version, trace_id, parent_span_id, flags = parts
        return nil if trace_id.nil? || trace_id.empty?

        {
          trace_id: trace_id,
          parent_span_id: parent_span_id,
          sampled: flags == SAMPLED_FLAG
        }
      end
    end
  end
end
