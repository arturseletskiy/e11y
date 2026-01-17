# frozen_string_literal: true

module E11y
  module Events
    # Base class for audit events
    #
    # Audit events are compliance-critical events that must never be lost.
    # They use the audit pipeline (Phase 4) which:
    # - Signs events for non-repudiation
    # - Encrypts sensitive data
    # - Routes to audit-specific storage
    # - Skips PII filtering (original data must be preserved)
    #
    # IMPORTANT: This base class does NOT set a default severity.
    # Users must explicitly set severity based on the event's criticality:
    # - :info for routine audit logging (e.g., "user viewed document")
    # - :warn for suspicious actions (e.g., "unauthorized access attempt")
    # - :error for violations (e.g., "failed authentication after 5 attempts")
    # - :fatal for critical security events (e.g., "security breach detected")
    #
    # @example Audit event with explicit severity
    #   class UserLoginAudit < E11y::Events::BaseAuditEvent
    #     severity :info  # Explicitly set based on criticality
    #
    #     schema do
    #       required(:user_id).filled(:integer)
    #       required(:ip_address).filled(:string)
    #       required(:timestamp).filled(:time)
    #     end
    #   end
    #
    #   UserLoginAudit.track(user_id: 123, ip_address: "192.168.1.1", timestamp: Time.now)
    class BaseAuditEvent < E11y::Event::Base
      include E11y::Presets::AuditEvent

      # Audit events use the audit pipeline (Phase 4)
      # For now, this is a marker - audit pipeline will be implemented later
      def self.audit_event?
        true
      end
    end
  end
end
