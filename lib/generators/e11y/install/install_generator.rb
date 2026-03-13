# frozen_string_literal: true

require "rails/generators"

module E11y
  module Generators
    # Creates config/initializers/e11y.rb and app/events/ directory scaffold.
    #
    # @example
    #   rails g e11y:install
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Creates an E11y initializer and the app/events/ directory."

      def create_initializer
        template "e11y.rb", "config/initializers/e11y.rb"
      end

      def create_events_directory
        empty_directory "app/events"
      end

      def show_readme
        say "\n✅ E11y installed!", :green
        say "   • config/initializers/e11y.rb — configure adapters here"
        say "   • app/events/               — put your event classes here"
        say "\nNext steps:"
        say "   rails g e11y:event OrderPaid   # generate an event class"
        say "   E11y.start!                    # call after configure in production\n"
      end
    end
  end
end
