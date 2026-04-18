# lib/e11y/adapters/action_mailer_adapter.rb
# frozen_string_literal: true

require_relative "notification_base"

module E11y
  module Adapters
    # Delivers event notifications via ActionMailer.
    #
    # Does NOT build email templates — delegates entirely to the user's mailer class.
    # The mailer receives structured data and renders its own templates.
    #
    # Notification behaviour (alert dedup / digest) is declared on the event:
    #
    #   class Events::DeployFailed < E11y::Event::Base
    #     notify do
    #       alert throttle_window: 1.hour, fingerprint: [:event_name]
    #     end
    #   end
    #
    # @example Mailer contract
    #   class AlertMailer < ApplicationMailer
    #     # event_data  — full event_data hash
    #     # recipients  — Array<String> configured on adapter
    #     def critical_alert(event_data, recipients)
    #       @event = event_data
    #       mail(to: recipients, subject: "Alert: #{event_data[:event_name]}")
    #     end
    #
    #     # digest_data — { events: [...], window_start:, window_end:,
    #     #                 total_count:, truncated:, truncated_count: }
    #     def digest(digest_data, recipients)
    #       @digest = digest_data
    #       mail(to: recipients, subject: "E11y Digest")
    #     end
    #   end
    #
    # @example Configuration
    #   E11y.configure do |config|
    #     config.register_adapter :email, E11y::Adapters::ActionMailerAdapter.new(
    #       mailer:        AlertMailer,
    #       alert_method:  :critical_alert,
    #       digest_method: :digest,
    #       recipients:    [ENV["OPS_EMAIL"]],
    #       delivery:      :later,
    #       store:         E11y::Store::RailsCache.new,
    #       max_event_types: 15
    #     )
    #   end
    class ActionMailerAdapter < NotificationBase
      # @param config [Hash]
      # @option config [Class]   :mailer        (required) ActionMailer subclass
      # @option config [Symbol]  :alert_method  method name for single-event alerts (default: :alert)
      # @option config [Symbol]  :digest_method method name for digest delivery (default: :digest)
      # @option config [Array]   :recipients    email addresses
      # @option config [Symbol]  :delivery      :now or :later (default: :later)
      # @option config [E11y::Store::Base] :store (required)
      # @option config [Integer] :max_event_types (default 20)
      def initialize(config = {})
        @mailer        = config[:mailer] or raise ArgumentError,
                                                  "#{self.class.name} requires :mailer"
        @alert_method  = config.fetch(:alert_method,  :alert)
        @digest_method = config.fetch(:digest_method, :digest)
        @recipients    = Array(config.fetch(:recipients, []))
        @delivery      = config.fetch(:delivery, :later)
        super
      end

      def adapter_id_source
        "action_mailer:#{@mailer}:#{@alert_method}:#{@digest_method}"
      end

      private

      def deliver_alert(event_data)
        mail = @mailer.public_send(@alert_method, event_data, @recipients)
        deliver_mail(mail)
      end

      # rubocop:disable Metrics/ParameterLists
      def deliver_digest(events:, window_start:, window_end:, total_count:, truncated:, truncated_count:)
        # rubocop:enable Metrics/ParameterLists
        digest_data = {
          events: events,
          window_start: window_start,
          window_end: window_end,
          total_count: total_count,
          truncated: truncated,
          truncated_count: truncated_count
        }
        mail = @mailer.public_send(@digest_method, digest_data, @recipients)
        deliver_mail(mail)
      end

      def deliver_mail(mail)
        case @delivery
        when :later then mail.deliver_later
        when :now   then mail.deliver_now
        else raise ArgumentError, "Unknown delivery mode: #{@delivery.inspect}. Use :now or :later"
        end
        true
      rescue StandardError => e
        warn "[E11y] ActionMailerAdapter delivery error: #{e.message}"
        false
      end

      def validate_config!
        # mailer presence already validated before super
      end
    end
  end
end
