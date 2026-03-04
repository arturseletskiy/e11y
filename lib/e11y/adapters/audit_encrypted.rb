# frozen_string_literal: true

require "openssl"
require "json"
require "fileutils"
require "base64"
require "e11y/event/base"

module E11y
  module Adapters
    # Audit Encrypted Adapter - AES-256-GCM encrypted storage for audit events
    #
    # Stores audit events with encryption at rest for compliance requirements.
    # Each event is individually encrypted with AES-256-GCM.
    #
    # **Security:**
    # - AES-256-GCM authenticated encryption
    # - Per-event nonce (never reused)
    # - Authentication tag validation
    # - Separate encryption key from signing key
    #
    # @example Configuration
    #   E11y.configure do |config|
    #     config.adapter :audit_encrypted do |a|
    #       a.storage_path = Rails.root.join('log', 'audit')
    #       a.encryption_key = ENV['E11Y_AUDIT_ENCRYPTION_KEY']
    #     end
    #   end
    #
    # @see ADR-006 §4.0 Audit Trail Security
    # @see UC-012 Audit Trail
    # rubocop:disable Metrics/ClassLength
    # Audit adapter contains encryption/decryption logic as cohesive unit
    class AuditEncrypted < Base
      # AES-256-GCM cipher
      CIPHER = "aes-256-gcm"

      # Encryption key (256 bits = 32 bytes)
      # Must be set via ENV or configuration
      attr_accessor :encryption_key

      # Storage path for encrypted audit logs
      attr_accessor :storage_path

      # Initialize adapter
      #
      # @param config [Hash] Configuration options
      def initialize(config = {})
        @encryption_key = config[:encryption_key] || default_encryption_key
        @storage_path = config[:storage_path] || default_storage_path

        super

        ensure_storage_directory!
      end

      # Write encrypted audit event
      #
      # @param event_data [Hash] Event data with signature
      # @return [Boolean] true on success, false on failure
      def write(event_data)
        # 1. Encrypt event data
        encrypted = encrypt_event(event_data)

        # 2. Write to storage
        write_to_storage(encrypted)
        true
      rescue StandardError => e
        warn "AuditEncrypted adapter error: #{e.message}"
        false
      end

      # Adapter capabilities
      #
      # @return [Hash] Capability flags
      def capabilities
        {
          batching: false,
          compression: false,
          async: false,
          streaming: false
        }
      end

      # Read and decrypt audit event (for verification)
      #
      # @param event_id [String] Event ID
      # @return [Hash, nil] Decrypted event data, or nil if decryption fails
      def read(event_id)
        encrypted_data = read_from_storage(event_id)
        decrypt_event(encrypted_data)
      rescue Errno::ENOENT => e
        warn "AuditEncrypted read error (file not found): #{e.message}"
        nil
      rescue JSON::ParserError => e
        warn "AuditEncrypted read error (corrupt data): #{e.message}"
        nil
      rescue OpenSSL::Cipher::CipherError => e
        # SECURITY: decryption failure indicates tampered or corrupt ciphertext.
        # Re-raise so callers can handle it; also attempt to emit a security event.
        track_security_event(event_id, e)
        raise
      end

      private

      # Emit a security event when decryption fails (potential tampering).
      # Guards against E11y not being fully configured in non-production envs.
      #
      # @param event_id [String] The event ID that failed to decrypt
      # @param error [OpenSSL::Cipher::CipherError] The decryption error
      # @return [void]
      def track_security_event(event_id, error)
        E11y::Event::Base.track(
          event_name: "e11y.security.audit_decryption_failed",
          severity: :error,
          payload: {
            event_id: event_id,
            error_class: error.class.name,
            error_message: error.message,
            adapter: self.class.name
          }
        )
      rescue StandardError
        warn "AuditEncrypted: decryption failure detected for #{event_id} " \
             "(#{error.message}); security event could not be tracked"
      end

      # Encrypt event data with AES-256-GCM
      #
      # @param event_data [Hash] Event data
      # @return [Hash] Encrypted data with nonce and tag
      def encrypt_event(event_data)
        cipher = OpenSSL::Cipher.new(CIPHER)
        cipher.encrypt
        cipher.key = encryption_key_bytes

        # Generate random nonce (never reuse!)
        nonce = cipher.random_iv

        # Serialize event data
        plaintext = JSON.generate(event_data)

        # Encrypt
        ciphertext = cipher.update(plaintext) + cipher.final

        # Get authentication tag
        auth_tag = cipher.auth_tag

        {
          encrypted_data: Base64.strict_encode64(ciphertext),
          nonce: Base64.strict_encode64(nonce),
          auth_tag: Base64.strict_encode64(auth_tag),
          event_name: event_data[:event_name],
          timestamp: event_data[:timestamp],
          cipher: CIPHER
        }
      end

      # Decrypt event data
      #
      # @param encrypted [Hash] Encrypted data with nonce and tag
      # @return [Hash] Decrypted event data
      # Cryptographic operations require multiple steps for secure decryption
      def decrypt_event(encrypted)
        cipher = OpenSSL::Cipher.new(CIPHER)
        cipher.decrypt
        cipher.key = encryption_key_bytes
        cipher.iv = Base64.strict_decode64(encrypted[:nonce])
        cipher.auth_tag = Base64.strict_decode64(encrypted[:auth_tag])

        ciphertext = Base64.strict_decode64(encrypted[:encrypted_data])
        plaintext = cipher.update(ciphertext) + cipher.final

        JSON.parse(plaintext, symbolize_names: true)
      end

      # Write encrypted data to storage
      #
      # @param encrypted [Hash] Encrypted data
      # @return [void]
      def write_to_storage(encrypted)
        # Generate filename with timestamp for sorting
        timestamp = Time.now.utc.strftime("%Y%m%d_%H%M%S_%6N")
        event_name = encrypted[:event_name].to_s.gsub("::", "_")
        filename = "#{timestamp}_#{event_name}.enc"

        filepath = ::File.join(storage_path, filename)

        # Write atomically
        ::File.write(filepath, JSON.generate(encrypted))
      end

      # Read encrypted data from storage
      #
      # @param event_id [String] Event ID (filename)
      # @return [Hash] Encrypted data
      def read_from_storage(event_id)
        filepath = ::File.join(storage_path, event_id)
        data = ::File.read(filepath)
        JSON.parse(data, symbolize_names: true)
      end

      # Validate configuration
      #
      # @raise [E11y::Error] if configuration invalid
      # @return [void]
      def validate_config!
        # Allow nil key for development (will use default)
        return if encryption_key.nil? && !production?

        if encryption_key && encryption_key.bytesize != 32
          raise E11y::Error, "Audit encryption key must be 32 bytes (256 bits), got #{encryption_key.bytesize}"
        end

        return unless storage_path.nil? || storage_path.empty?

        raise E11y::Error, "Audit storage path must be set"
      end

      # Check if running in production
      #
      # @return [Boolean]
      def production?
        defined?(::Rails) && ::Rails.env.production?
      end

      # Ensure storage directory exists
      #
      # @return [void]
      def ensure_storage_directory!
        FileUtils.mkdir_p(storage_path)
      end

      # Get encryption key as bytes
      #
      # @return [String] Encryption key bytes
      def encryption_key_bytes
        @encryption_key_bytes ||= if encryption_key.bytesize == 32
                                    encryption_key
                                  else
                                    # Hex-decode if provided as hex string
                                    [encryption_key].pack("H*")
                                  end
      end

      # Default encryption key (development only)
      #
      # @return [String] Encryption key
      def default_encryption_key
        # Use ENV var if provided (required in production)
        env_key = ENV.fetch("E11Y_AUDIT_ENCRYPTION_KEY", nil)
        if env_key
          return env_key.bytesize == 32 ? env_key : [env_key].pack("H*")
        end

        # In production without ENV var, raise a clear error
        if defined?(::Rails) && ::Rails.env.production?
          raise E11y::Error,
                "E11Y_AUDIT_ENCRYPTION_KEY must be set in production. " \
                "Generate with: openssl rand -hex 32"
        end

        # Development/test: derive a stable key from a fixed seed.
        # This is NOT secure for production — only for development/testing.
        OpenSSL::PKCS5.pbkdf2_hmac_sha1(
          "e11y-development-key-not-for-production",
          "e11y-static-salt",
          1000,
          32
        )
      end

      # Default storage path
      #
      # @return [String] Storage path
      def default_storage_path
        if defined?(::Rails) && ::Rails.root
          ::Rails.root.join("log", "audit").to_s
        else
          ::File.join(Dir.pwd, "log", "audit")
        end
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
