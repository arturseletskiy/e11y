# frozen_string_literal: true

require "rails_helper"

# Integration tests for UC-022: Event Registry
#
# These tests verify the Registry against real event classes defined in spec/dummy,
# along with full pipeline interaction to ensure auto-registration does not interfere
# with normal event tracking.
RSpec.describe "Event Registry Integration", :integration do
  # Use the singleton registry.
  # Clear before and after each test for isolation.
  let(:registry) { E11y::Registry.instance }

  before { registry.clear! }
  after  { registry.clear! }

  # -------------------------------------------------------------------------
  # Manual registration of known dummy app event classes
  # -------------------------------------------------------------------------
  describe "registering real event classes" do
    before do
      # Dummy events use auto-derived names (no explicit event_name call),
      # so they are not auto-registered. We register them explicitly here.
      [
        Events::OrderCreated,
        Events::OrderPaid,
        Events::PaymentFailed,
        Events::UserRegistered,
        Events::UserDeleted
      ].each { |klass| registry.register(klass) }
    end

    it "finds Events::OrderCreated by its derived name" do
      result = registry.find("Events::OrderCreated")
      expect(result).to eq(Events::OrderCreated)
    end

    it "finds Events::OrderPaid by its derived name" do
      result = registry.find("Events::OrderPaid")
      expect(result).to eq(Events::OrderPaid)
    end

    it "finds Events::PaymentFailed by its derived name" do
      result = registry.find("Events::PaymentFailed")
      expect(result).to eq(Events::PaymentFailed)
    end

    it "all five registered classes appear in all_events" do
      all = registry.all_events
      expect(all).to include(
        Events::OrderCreated,
        Events::OrderPaid,
        Events::PaymentFailed,
        Events::UserRegistered,
        Events::UserDeleted
      )
    end

    it "size equals the number of unique event names registered" do
      expect(registry.size).to eq(5)
    end
  end

  # -------------------------------------------------------------------------
  # Auto-registration via event_name DSL setter
  # -------------------------------------------------------------------------
  describe "auto-registration via event_name DSL setter" do
    it "registers a new event class as soon as event_name is called" do
      unique_name = "integration.auto.#{rand(100_000)}"

      klass = Class.new(E11y::Event::Base) do
        contains_pii false
        adapters []
      end
      klass.event_name(unique_name)

      expect(registry.find(unique_name)).to eq(klass)
    end

    it "E11y.registry returns the same singleton" do
      expect(E11y.registry).to be(E11y::Registry.instance)
    end
  end

  # -------------------------------------------------------------------------
  # Filtering (where)
  # -------------------------------------------------------------------------
  describe ".where filtering" do
    before do
      registry.register(Events::PaymentFailed) # auto-resolved severity :error
      registry.register(Events::OrderCreated)  # auto-resolved severity :success
    end

    it "filters to error-severity events" do
      result = registry.where(severity: :error)
      expect(result).to include(Events::PaymentFailed)
    end

    it "excludes non-matching events" do
      result = registry.where(severity: :error)
      expect(result).not_to include(Events::OrderCreated)
    end
  end

  # -------------------------------------------------------------------------
  # validate
  # -------------------------------------------------------------------------
  describe ".validate" do
    before do
      registry.register(Events::OrderPaid)
      registry.register(Events::OrderCreated)
    end

    it "returns true for Events::OrderPaid which has a schema" do
      expect(registry.validate("Events::OrderPaid")).to be(true)
    end

    it "returns false for an unregistered event name" do
      expect(registry.validate("Events::DoesNotExist")).to be(false)
    end
  end

  # -------------------------------------------------------------------------
  # to_documentation
  # -------------------------------------------------------------------------
  describe ".to_documentation" do
    before do
      registry.register(Events::OrderPaid)
      registry.register(Events::PaymentFailed)
    end

    it "returns an array of documentation hashes" do
      docs = registry.to_documentation
      expect(docs).to be_an(Array)
      expect(docs.size).to eq(2)
    end

    it "includes :name, :class, :version, :severity for each entry" do
      docs = registry.to_documentation
      docs.each do |doc|
        expect(doc).to have_key(:name)
        expect(doc).to have_key(:class)
        expect(doc).to have_key(:version)
        expect(doc).to have_key(:severity)
      end
    end

    it "includes :schema_keys for events that have schemas" do
      docs = registry.to_documentation
      paid_doc = docs.find { |d| d[:class] == "Events::OrderPaid" }
      expect(paid_doc[:schema_keys]).to include("order_id", "currency")
    end
  end

  # -------------------------------------------------------------------------
  # Registry does not interfere with event pipeline
  # -------------------------------------------------------------------------
  describe "registry does not interfere with event pipeline" do
    let(:memory_adapter) { E11y.config.adapters[:memory] }

    before { memory_adapter&.clear! }

    it "registered events can still be tracked normally" do
      registry.register(Events::OrderPaid)

      expect do
        Events::OrderPaid.track(order_id: "ORD-999", currency: "USD")
      end.not_to raise_error
    end
  end
end
