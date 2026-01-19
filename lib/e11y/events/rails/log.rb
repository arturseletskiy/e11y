# frozen_string_literal: true

require "e11y/event/base"

module E11y
  module Events
    module Rails
      # Base class for all Rails.logger events
      #
      # This is an ABSTRACT class - use specific severity classes instead:
      # - Events::Rails::Log::Debug
      # - Events::Rails::Log::Info
      # - Events::Rails::Log::Warn
      # - Events::Rails::Log::Error
      # - Events::Rails::Log::Fatal
      #
      # @see E11y::Logger::Bridge
      class Log < E11y::Event::Base
        schema do
          required(:message).filled(:string)
          optional(:caller_location).filled(:string)
        end

        # Debug logs (verbose, typically disabled in production)
        class Debug < Log
          severity :debug
          adapters [:logs]
        end

        # Info logs (general information)
        class Info < Log
          severity :info
          adapters [:logs]
        end

        # Warning logs (potential issues)
        class Warn < Log
          severity :warn
          adapters [:logs]
        end

        # Error logs (errors that need attention)
        class Error < Log
          severity :error
          adapters %i[logs errors_tracker] # Send to Sentry!
        end

        # Fatal logs (critical errors, system-breaking)
        class Fatal < Log
          severity :fatal
          adapters %i[logs errors_tracker] # Send to Sentry!
        end
      end
    end
  end
end
