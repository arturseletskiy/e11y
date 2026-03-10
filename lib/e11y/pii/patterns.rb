# frozen_string_literal: true

module E11y
  module PII
    # Universal PII patterns for automatic detection
    #
    # Patterns are used by PIIFiltering middleware to automatically detect
    # and mask/hash sensitive data in event payloads.
    #
    # @see E11y::Middleware::PIIFiltering
    # @see ADR-006 PII Security
    # @see UC-007 PII Filtering
    module Patterns
      # Email pattern (RFC 5322 simplified)
      EMAIL = /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/

      # Password-like field names
      PASSWORD_FIELDS = /\b(?:password|passwd|pwd|secret|token|api[_-]?key)\b/i

      # Social Security Number (US format: XXX-XX-XXXX)
      SSN = /\b\d{3}-\d{2}-\d{4}\b/

      # Credit card number (Visa, MC, Amex, Discover)
      # Luhn algorithm validation not included (performance trade-off)
      CREDIT_CARD = /\b(?:\d{4}[- ]?){3}\d{4}\b/

      # IPv4 address
      IPV4 = /\b(?:\d{1,3}\.){3}\d{1,3}\b/

      # Phone number (various formats)
      PHONE = /\b(?:\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b/

      # All patterns combined for bulk detection
      ALL = [
        EMAIL,
        PASSWORD_FIELDS,
        SSN,
        CREDIT_CARD,
        IPV4,
        PHONE
      ].freeze

      # Field name patterns that indicate PII
      # Used for field-level detection (case-insensitive)
      FIELD_PATTERNS = {
        email: /email|e[_-]?mail/i,
        password: /password|passwd|pwd|secret|token|api[_-]?key/i,
        ssn: /ssn|social[_-]?security|tax[_-]?id/i,
        credit_card: /card|cc[_-]?number|credit[_-]?card|pan/i,
        phone: /phone|mobile|tel|telephone/i,
        ip: /\Aip\z|ip[_-]?address|remote[_-]?addr/i,
        address: /\Aaddress\z|street|city|zip|postal/i,
        name: /name|first[_-]?name|last[_-]?name|full[_-]?name/i,
        dob: /birth|dob|date[_-]?of[_-]?birth/i
      }.freeze

      # Check if field name matches PII pattern
      #
      # @param field_name [String, Symbol] Field name to check
      # @return [Symbol, nil] PII type if matched, nil otherwise
      #
      # @example
      #   Patterns.detect_field_type(:email) # => :email
      #   Patterns.detect_field_type(:user_email) # => :email
      #   Patterns.detect_field_type(:id) # => nil
      def self.detect_field_type(field_name)
        field_str = field_name.to_s
        FIELD_PATTERNS.each do |type, pattern|
          return type if field_str.match?(pattern)
        end
        nil
      end

      # Check if value matches any PII pattern
      #
      # @param value [String] Value to check
      # @return [Boolean] true if PII detected
      #
      # @example
      #   Patterns.contains_pii?("user@example.com") # => true
      #   Patterns.contains_pii?("123-45-6789") # => true
      #   Patterns.contains_pii?("hello world") # => false
      def self.contains_pii?(value)
        return false unless value.is_a?(String)

        ALL.any? { |pattern| value.match?(pattern) }
      end
    end
  end
end
