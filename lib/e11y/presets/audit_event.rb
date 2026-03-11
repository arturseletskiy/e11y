# frozen_string_literal: true

module E11y
  module Presets
    # Preset for audit events (compliance-critical)
    #
    # Audit events are compliance-critical events that must never be lost,
    # regardless of their severity level. They use a separate audit pipeline that:
    # - Signs events for non-repudiation
    # - Encrypts sensitive data
    # - Routes to audit-specific storage
    # - Skips PII filtering (original data must be preserved)
    #
    # IMPORTANT: Audit events can have ANY severity (info, warn, error, fatal).
    # The severity should be set by the user based on the event's criticality.
    #
    # @example Audit event with info severity (just logging an action)
    #   class UserViewedDocumentAudit < E11y::Event::Base
    #     include E11y::Presets::AuditEvent
    #     severity :info  # User explicitly sets severity
    #
    #     schema do
    #       required(:user_id).filled(:integer)
    #       required(:document_id).filled(:integer)
    #     end
    #   end
    #
    # @example Audit event with fatal severity (security breach)
    #   class SecurityBreachAudit < E11y::Event::Base
    #     include E11y::Presets::AuditEvent
    #     severity :fatal  # User explicitly sets severity
    #
    #     schema do
    #       required(:breach_type).filled(:string)
    #       required(:affected_users).filled(:integer)
    #     end
    #   end
    module AuditEvent
      def self.included(base)
        base.class_eval do
          audit_event true
          # Severity is NOT set by preset - user decides based on event criticality
        end

        # Extend class with audit-specific methods (resolve_sample_rate 1.0, resolve_rate_limit nil)
        base.extend(ClassMethods)
      end

      # Class methods for audit events
      module ClassMethods
        # Override resolve_rate_limit to unlimited for audit events
        # Audit events must NEVER be dropped, regardless of severity
        def resolve_rate_limit
          nil # Unlimited - compliance requirement
        end

        # Override resolve_sample_rate to 100% for audit events
        # Audit events must ALL be tracked, regardless of severity
        def resolve_sample_rate
          1.0 # 100% - compliance requirement
        end
      end
    end
  end
end
