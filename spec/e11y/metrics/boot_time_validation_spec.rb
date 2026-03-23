# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/DescribeClass
# Integration test for boot-time validation, tests cross-cutting concern
RSpec.describe "E11y::Metrics Boot-Time Validation" do
  let(:registry) { E11y::Metrics::Registry.instance }

  before do
    # Clear registry before each test
    registry.clear!
  end

  describe "Registry#validate_all!" do
    context "with no conflicts" do
      it "validates successfully" do
        registry.register(
          type: :counter,
          pattern: "order.*",
          name: :orders_total,
          tags: %i[currency status],
          source: "Event1"
        )

        registry.register(
          type: :counter,
          pattern: "order.paid",
          name: :orders_total,
          tags: %i[currency status], # Same tags - OK
          source: "Event2"
        )

        expect { registry.validate_all! }.not_to raise_error
      end

      it "validates when only one metric registered" do
        registry.register(
          type: :counter,
          pattern: "order.*",
          name: :orders_total,
          tags: [:status],
          source: "Event1"
        )

        expect { registry.validate_all! }.not_to raise_error
      end

      it "validates when metrics have different names" do
        registry.register(
          type: :counter,
          pattern: "order.*",
          name: :orders_total,
          tags: [:status],
          source: "Event1"
        )

        registry.register(
          type: :counter,
          pattern: "order.*",
          name: :orders_count, # Different name - OK
          tags: [:currency],
          source: "Event2"
        )

        expect { registry.validate_all! }.not_to raise_error
      end
    end

    context "with label conflicts" do
      it "raises LabelConflictError immediately during registration" do
        registry.register(
          type: :counter,
          pattern: "order.*",
          name: :orders_total,
          tags: %i[currency status],
          source: "Event1"
        )

        # Conflict detected immediately during registration (fail-fast)
        expect do
          registry.register(
            type: :counter,
            pattern: "order.paid",
            name: :orders_total,
            tags: [:currency], # Different labels!
            source: "Event2"
          )
        end.to raise_error(
          E11y::Metrics::Registry::LabelConflictError,
          /label conflict/
        )
      end

      it "includes source information in error during registration" do
        registry.register(
          type: :counter,
          pattern: "order.*",
          name: :orders_total,
          tags: [:status],
          source: "Events::OrderCreated.metrics"
        )

        expect do
          registry.register(
            type: :counter,
            pattern: "order.paid",
            name: :orders_total,
            tags: [:currency],
            source: "Events::OrderPaid.metrics"
          )
        end.to raise_error do |error| # rubocop:todo Style/MultilineBlockChain
          expect(error.message).to include("Events::OrderCreated.metrics")
          expect(error.message).to include("Events::OrderPaid.metrics")
        end
      end
    end

    context "with type conflicts" do
      it "raises TypeConflictError immediately during registration" do
        registry.register(
          type: :counter,
          pattern: "order.*",
          name: :orders_total,
          tags: [:status],
          source: "Event1"
        )

        expect do
          registry.register(
            type: :histogram, # Different type!
            pattern: "order.paid",
            name: :orders_total,
            value: :amount,
            tags: [:status],
            source: "Event2"
          )
        end.to raise_error(
          E11y::Metrics::Registry::TypeConflictError,
          /type conflict/
        )
      end
    end

    context "with multiple conflicts" do
      it "reports first conflict immediately during registration" do
        # Register first metric
        registry.register(
          type: :counter,
          pattern: "order.*",
          name: :orders_total,
          tags: %i[currency status],
          source: "Event1"
        )

        # Second registration fails immediately (fail-fast)
        expect do
          registry.register(
            type: :counter,
            pattern: "order.paid",
            name: :orders_total,
            tags: [:currency], # Conflict 1
            source: "Event2"
          )
        end.to raise_error(E11y::Metrics::Registry::LabelConflictError)

        # Third registration would never happen (already failed)
      end
    end

    context "with complex scenarios" do
      # Integration test requires multiple metric registrations for validation
      it "validates multiple metric groups" do
        # Group 1: orders_total (valid)
        registry.register(
          type: :counter,
          pattern: "order.*",
          name: :orders_total,
          tags: [:status],
          source: "Event1"
        )

        registry.register(
          type: :counter,
          pattern: "order.paid",
          name: :orders_total,
          tags: [:status], # Same - OK
          source: "Event2"
        )

        # Group 2: users_total (valid)
        registry.register(
          type: :counter,
          pattern: "user.*",
          name: :users_total,
          tags: [:role],
          source: "Event3"
        )

        # Group 3: api_duration (valid)
        registry.register(
          type: :histogram,
          pattern: "api.*",
          name: :api_duration,
          value: :duration,
          tags: [:endpoint],
          source: "Event4"
        )

        expect { registry.validate_all! }.not_to raise_error
      end

      # Integration test requires multiple metric registrations for conflict detection
      it "detects conflict immediately during registration" do
        # Group 1: orders_total (valid)
        registry.register(
          type: :counter,
          pattern: "order.*",
          name: :orders_total,
          tags: [:status],
          source: "Event1"
        )

        registry.register(
          type: :counter,
          pattern: "order.paid",
          name: :orders_total,
          tags: [:status], # Same - OK
          source: "Event2"
        )

        # Group 2: users_total (first registration OK)
        registry.register(
          type: :counter,
          pattern: "user.*",
          name: :users_total,
          tags: [:role],
          source: "Event3"
        )

        # Conflict detected immediately on second registration
        expect do
          registry.register(
            type: :counter,
            pattern: "user.signup",
            name: :users_total,
            tags: %i[role tier], # Different labels - CONFLICT!
            source: "Event4"
          )
        end.to raise_error(E11y::Metrics::Registry::LabelConflictError)
      end
    end
  end

  describe "Integration with Event::Base" do
    it "catches conflicts when defining event classes" do
      # First event
      Class.new(E11y::Event::Base) do
        define_singleton_method(:name) { "Events::OrderCreated" }

        metrics do
          counter :orders_total, tags: %i[currency status]
        end
      end

      # Second event with conflicting metric
      expect do
        Class.new(E11y::Event::Base) do
          define_singleton_method(:name) { "Events::OrderPaid" }

          metrics do
            counter :orders_total, tags: [:currency] # Different labels!
          end
        end
      end.to raise_error(E11y::Metrics::Registry::LabelConflictError)
    end

    it "allows same metric with same configuration" do
      # First event
      Class.new(E11y::Event::Base) do
        define_singleton_method(:name) { "Events::OrderCreated" }

        metrics do
          counter :orders_total, tags: %i[currency status]
        end
      end

      # Second event with same metric config
      expect do
        Class.new(E11y::Event::Base) do
          define_singleton_method(:name) { "Events::OrderPaid" }

          metrics do
            counter :orders_total, tags: %i[currency status] # Same - OK
          end
        end
      end.not_to raise_error
    end
  end
end
# rubocop:enable RSpec/DescribeClass
