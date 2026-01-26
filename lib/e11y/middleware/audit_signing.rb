# frozen_string_literal: true

require "openssl"
require "json"

module E11y
  module Middleware
    # Audit Signing Middleware - HMAC-SHA256 signatures for audit events
    #
    # Signs audit events with HMAC-SHA256 before any transformations (including PII filtering).
    # This ensures cryptographic proof of event authenticity for compliance.
    #
    # **Critical Design:**
    # - Signs ORIGINAL data (before PII filtering) for legal compliance
    # - Only processes events marked as audit events
    # - Runs in :security zone BEFORE other middleware
    #
    # @example Audit Event
    #   class Events::UserDeleted < E11y::Event::Base
    #     audit_event true
    #
    #     schema do
    #       required(:user_id).filled(:integer)
    #       required(:deleted_by).filled(:integer)
    #       required(:ip_address).filled(:string)
    #     end
    #   end
    #
    #   Events::UserDeleted.track(
    #     user_id: 123,
    #     deleted_by: 456,
    #     ip_address: "192.168.1.1"  # Original IP preserved
    #   )
    #
    #   # Result: Signed with HMAC-SHA256 before PII filtering
    #
    # @see ADR-006 §4.0 Audit Trail Security
    # @see UC-012 Audit Trail
    class AuditSigning < Base
      middleware_zone :security

      # Get HMAC signing key (from ENV or generated)
      # @return [String] Signing key
      def self.signing_key
        @signing_key ||= ENV.fetch("E11Y_AUDIT_SIGNING_KEY") do
          # Development fallback (NOT for production!)
          if defined?(::Rails) && ::Rails.env.production?
            raise E11y::Error, "E11Y_AUDIT_SIGNING_KEY must be set in production"
          end

          "development_key_#{SecureRandom.hex(32)}"
        end
      end

      # Initialize audit signing middleware
      #
      # @param app [Proc] Next middleware in chain

      # Process event and sign if it's an audit event
      #
      # @param event_data [Hash] Event data with payload
      # @return [Hash] Event data with signature
      def call(event_data)
        # Only sign audit events that require signing
        if audit_event?(event_data) && requires_signing?(event_data)
          signed_data = sign_event(event_data)
          @app.call(signed_data)
        else
          # Non-audit events OR signing disabled: pass through
          @app.call(event_data)
        end
      end

      # Verify signature (for testing/validation)
      #
      # @param event_data [Hash] Event data with signature
      # @return [Boolean] true if signature is valid
      # rubocop:disable Naming/PredicateMethod
      def self.verify_signature(event_data)
        expected_signature = event_data[:audit_signature]
        canonical = event_data[:audit_canonical]

        return false unless expected_signature && canonical

        actual_signature = OpenSSL::HMAC.hexdigest("SHA256", signing_key, canonical)
        actual_signature == expected_signature
      end
      # rubocop:enable Naming/PredicateMethod

      private

      # Check if event is marked as audit event
      #
      # @param event_data [Hash] Event data
      # @return [Boolean] true if audit event
      def audit_event?(event_data)
        event_class = event_data[:event_class]
        event_class.respond_to?(:audit_event?) && event_class.audit_event?
      end

      # Check if event requires signing
      #
      # Signing is enabled by default for all audit events.
      # Can be disabled via `signing enabled: false` DSL.
      #
      # @param event_data [Hash] Event data
      # @return [Boolean] true if signing required
      def requires_signing?(event_data)
        event_class = event_data[:event_class]

        # Default: true (sign all audit events unless explicitly disabled)
        return true unless event_class.respond_to?(:signing_enabled?)

        event_class.signing_enabled?
      end

      # Sign event with HMAC-SHA256
      #
      # @param event_data [Hash] Event data
      # @return [Hash] Event data with signature
      def sign_event(event_data)
        # 1. Create canonical representation (sorted JSON for consistency)
        canonical = canonical_representation(event_data)

        # 2. Generate HMAC-SHA256 signature
        signature = generate_signature(canonical)

        # 3. Add signature metadata
        event_data.merge(
          audit_signature: signature,
          audit_signed_at: Time.now.utc.iso8601(6),
          audit_canonical: canonical
        )
      end

      # Create canonical representation for signing
      #
      # @param event_data [Hash] Event data
      # @return [String] Canonical JSON string
      def canonical_representation(event_data)
        # Extract fields that should be signed
        signable_data = {
          event_name: event_data[:event_name],
          payload: event_data[:payload],
          timestamp: event_data[:timestamp],
          version: event_data[:version]
        }

        # Convert to sorted JSON (deterministic)
        JSON.generate(sort_hash(signable_data))
      end

      # Generate HMAC-SHA256 signature
      #
      # @param data [String] Data to sign
      # @return [String] Hex-encoded signature
      def generate_signature(data)
        OpenSSL::HMAC.hexdigest("SHA256", self.class.signing_key, data)
      end

      # Sort hash recursively for deterministic JSON
      #
      # @param obj [Object] Object to sort
      # @return [Object] Sorted object
      def sort_hash(obj)
        case obj
        when Hash
          obj.keys.sort.to_h { |k| [k, sort_hash(obj[k])] }
        when Array
          obj.map { |v| sort_hash(v) }
        else
          obj
        end
      end
    end
  end
end
