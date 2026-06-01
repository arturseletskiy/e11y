# lib/e11y/adapters/mattermost_adapter.rb
# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require_relative "notification_base"

module E11y
  module Adapters
    # Delivers event notifications to Mattermost via Incoming Webhook.
    #
    # Notification behaviour (alert dedup / digest) is declared on the event:
    #
    #   class Events::PaymentFailed < E11y::Event::Base
    #     notify do
    #       alert throttle_window: 30.minutes, fingerprint: [:event_name]
    #     end
    #   end
    #
    # @example Configuration
    #   E11y.configure do |config|
    #     config.register_adapter :mattermost, E11y::Adapters::MattermostAdapter.new(
    #       webhook_url:     ENV["MATTERMOST_WEBHOOK"],
    #       channel:         "#production-alerts",
    #       store:           E11y::Store::RailsCache.new,
    #       max_event_types: 20
    #     )
    #   end
    class MattermostAdapter < NotificationBase
      SEVERITY_EMOJI = {
        debug: "⚪",
        info: "🔵",
        success: "🟢",
        warn: "🟡",
        error: "🔴",
        fatal: "🔴"
      }.freeze

      # @param config [Hash]
      # @option config [String]  :webhook_url (required)
      # @option config [String]  :channel     (optional, e.g. "#alerts")
      # @option config [String]  :username    (optional, default "E11y")
      # @option config [E11y::Store::Base] :store (required)
      # @option config [Integer] :max_event_types (default 20)
      def initialize(config = {})
        @webhook_url = config[:webhook_url] or raise ArgumentError,
                                                     "#{self.class.name} requires :webhook_url"
        @channel     = config[:channel]
        @username    = config.fetch(:username, "E11y")
        super
      end

      def healthy?
        !@webhook_url.nil? && !@store.nil?
      end

      def adapter_id_source
        "mattermost:#{@webhook_url}"
      end

      private

      def deliver_alert(event_data)
        call_webhook(format_alert(event_data))
      end

      # rubocop:disable Metrics/ParameterLists
      def deliver_digest(events:, window_start:, window_end:, total_count:, truncated:, truncated_count:)
        text = format_digest(
          events: events,
          window_start: window_start,
          window_end: window_end,
          total_count: total_count,
          truncated: truncated,
          truncated_count: truncated_count
        )
        call_webhook(text)
      end
      # rubocop:enable Metrics/ParameterLists

      def format_alert(event_data)
        emoji = SEVERITY_EMOJI.fetch(event_data[:severity], "⚪")
        lines = ["#{emoji} **#{event_data[:event_name]}** (#{event_data[:severity]})"]
        lines << event_data[:message].to_s if event_data[:message]

        payload = event_data[:payload]
        lines.concat(payload.map { |k, v| "**#{k}:** #{v}" }) if payload.is_a?(Hash) && payload.any?

        trace = event_data.dig(:context, :trace_id)
        lines << "_trace: #{trace}_" if trace

        lines.join("\n")
      end

      # rubocop:disable Metrics/ParameterLists
      def format_digest(events:, window_start:, window_end:, total_count:, truncated:, truncated_count:)
        # rubocop:enable Metrics/ParameterLists
        lines = ["📊 **E11y Digest** · #{window_start.strftime('%H:%M')}–#{window_end.strftime('%H:%M')}"]
        lines << ""

        events.each do |e|
          emoji = SEVERITY_EMOJI.fetch(e[:severity], "⚪")
          lines << "#{emoji} #{e[:event_name].to_s.ljust(35)} × #{e[:count]}"
        end

        lines << "_… and #{truncated_count} more event type(s)_" if truncated
        lines << ""
        lines << "Total: **#{total_count}** events"
        lines.join("\n")
      end

      # Raises internally on non-2xx response or network error;
      # all exceptions are rescued by Throttleable#write which returns false.
      def call_webhook(text)
        payload = { text: text, username: @username }
        payload[:channel] = @channel if @channel

        response = execute_http_request(payload.to_json)
        raise "Mattermost webhook returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        nil
      end

      def execute_http_request(body)
        uri  = URI.parse(@webhook_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl      = uri.scheme == "https"
        http.open_timeout = 5
        http.read_timeout = 10

        request                 = Net::HTTP::Post.new(uri.request_uri)
        request["Content-Type"] = "application/json"
        request.body            = body

        http.request(request)
      end

      def validate_config!
        # webhook_url already validated before super
      end
    end
  end
end
