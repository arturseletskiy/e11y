# frozen_string_literal: true

require "rails/generators"

module E11y
  module Generators
    # Generates an event class under app/events/.
    #
    # @example
    #   rails g e11y:event OrderPaid
    #   # => creates app/events/events/order_paid.rb
    class EventGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      desc "Creates an E11y event class in app/events/."

      def create_event_file
        template "event.rb.tt", File.join("app/events/events", "#{file_name}.rb")
      end
    end
  end
end
