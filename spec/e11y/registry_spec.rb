# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::Registry do
  # Use a LOCAL instance for most tests to avoid polluting the global singleton.
  # Only the auto-registration and singleton tests use the global instance.
  let(:registry) { described_class.new }

  # -------------------------------------------------------------------------
  # .register
  # -------------------------------------------------------------------------
  describe "#register" do
    it "registers an event class" do
      klass = Class.new(E11y::Event::Base) do
        contains_pii false
        event_name "test.registered"
      end
      registry.register(klass)
      expect(registry.find("test.registered")).to eq(klass)
    end

    it "ignores classes that do not respond to event_name" do
      klass = Class.new
      expect { registry.register(klass) }.not_to raise_error
      expect(registry.size).to eq(0)
    end

    it "ignores classes whose event_name returns nil" do
      klass = Class.new do
        def self.event_name
          nil
        end
      end
      registry.register(klass)
      expect(registry.size).to eq(0)
    end

    it "ignores classes whose event_name returns an empty string" do
      klass = Class.new do
        def self.event_name
          ""
        end
      end
      registry.register(klass)
      expect(registry.size).to eq(0)
    end

    it "is idempotent — double-registering the same class counts as one entry" do
      klass = Class.new(E11y::Event::Base) do
        contains_pii false
        event_name "test.idempotent"
      end
      registry.register(klass)
      registry.register(klass)
      entries = registry.all_events
      expect(entries.count { |k| k == klass }).to eq(1)
    end

    it "supports multiple classes sharing the same event name (versioning)" do
      v1 = Class.new(E11y::Event::Base) do
        contains_pii false
        event_name "order.created"
      end
      v2 = Class.new(E11y::Event::Base) do
        contains_pii false
        event_name "order.created"
      end
      registry.register(v1)
      registry.register(v2)
      # both are stored
      expect(registry.all_events).to include(v1, v2)
      # find returns the latest (last registered)
      expect(registry.find("order.created")).to eq(v2)
    end

    it "does not raise when event_name raises an error" do
      klass = Class.new do
        def self.event_name
          raise "boom"
        end
      end
      expect { registry.register(klass) }.not_to raise_error
      expect(registry.size).to eq(0)
    end
  end

  # -------------------------------------------------------------------------
  # #find
  # -------------------------------------------------------------------------
  describe "#find" do
    it "returns nil for an unknown event name" do
      expect(registry.find("unknown.event")).to be_nil
    end

    it "accepts a symbol as event name" do
      klass = Class.new(E11y::Event::Base) do
        contains_pii false
        event_name "ev.symbol"
      end
      registry.register(klass)
      expect(registry.find(:"ev.symbol")).to eq(klass)
    end

    it "returns the latest-registered class by default" do
      v1 = Class.new(E11y::Event::Base) do
        contains_pii false
        event_name "order.paid"
      end
      v2 = Class.new(E11y::Event::Base) do
        contains_pii false
        event_name "order.paid"
      end
      registry.register(v1)
      registry.register(v2)
      expect(registry.find("order.paid")).to eq(v2)
    end

    it "returns nil for a known name when version is not found" do
      klass = Class.new(E11y::Event::Base) do
        contains_pii false
        event_name "ev.versioned"
      end
      registry.register(klass)
      expect(registry.find("ev.versioned", version: 99)).to be_nil
    end

    it "returns the matching class when version is found" do
      v1 = Class.new(E11y::Event::Base) do
        contains_pii false
        event_name "ev.ver"
        version 1
      end
      v2 = Class.new(E11y::Event::Base) do
        contains_pii false
        event_name "ev.ver"
        version 2
      end
      registry.register(v1)
      registry.register(v2)
      expect(registry.find("ev.ver", version: 1)).to eq(v1)
      expect(registry.find("ev.ver", version: 2)).to eq(v2)
    end
  end

  # -------------------------------------------------------------------------
  # #all_events
  # -------------------------------------------------------------------------
  describe "#all_events" do
    it "returns an empty array when nothing is registered" do
      expect(registry.all_events).to eq([])
    end

    it "returns all registered event classes" do
      k1 = Class.new(E11y::Event::Base) do
        contains_pii false
        event_name "ev.one"
      end
      k2 = Class.new(E11y::Event::Base) do
        contains_pii false
        event_name "ev.two"
      end
      registry.register(k1)
      registry.register(k2)
      expect(registry.all_events).to contain_exactly(k1, k2)
    end

    it "returns a copy — mutating the result does not affect the registry" do
      k1 = Class.new(E11y::Event::Base) do
        contains_pii false
        event_name "ev.mutation"
      end
      registry.register(k1)
      result = registry.all_events
      result.clear
      expect(registry.all_events).not_to be_empty
    end
  end

  # -------------------------------------------------------------------------
  # #size
  # -------------------------------------------------------------------------
  describe "#size" do
    it "returns 0 for an empty registry" do
      expect(registry.size).to eq(0)
    end

    it "counts unique event names (not total class entries)" do
      k1 = Class.new(E11y::Event::Base) do
        contains_pii false
        event_name "ev.a"
      end
      k2 = Class.new(E11y::Event::Base) do
        contains_pii false
        event_name "ev.b"
      end
      k3 = Class.new(E11y::Event::Base) do
        contains_pii false
        event_name "ev.a" # same name as k1 — should count as 1
      end
      registry.register(k1)
      registry.register(k2)
      registry.register(k3)
      expect(registry.size).to eq(2)
    end
  end

  # -------------------------------------------------------------------------
  # #clear!
  # -------------------------------------------------------------------------
  describe "#clear!" do
    it "empties the registry" do
      klass = Class.new(E11y::Event::Base) do
        contains_pii false
        event_name "ev.to_clear"
      end
      registry.register(klass)
      registry.clear!
      expect(registry.size).to eq(0)
    end

    it "returns an empty array from all_events after clearing" do
      klass = Class.new(E11y::Event::Base) do
        contains_pii false
        event_name "ev.clear2"
      end
      registry.register(klass)
      registry.clear!
      expect(registry.all_events).to eq([])
    end
  end

  # -------------------------------------------------------------------------
  # #validate
  # -------------------------------------------------------------------------
  describe "#validate" do
    it "returns false for an unknown event" do
      expect(registry.validate("unknown.event")).to be(false)
    end

    it "returns false for a registered event without a schema" do
      klass = Class.new(E11y::Event::Base) do
        contains_pii false
        event_name "ev.noschema"
      end
      registry.register(klass)
      expect(registry.validate("ev.noschema")).to be(false)
    end

    it "returns true for a registered event that has a schema" do
      klass = Class.new(E11y::Event::Base) do
        event_name "ev.valid"
        contains_pii false
        schema do
          required(:id).filled(:string)
        end
      end
      registry.register(klass)
      expect(registry.validate("ev.valid")).to be(true)
    end
  end

  # -------------------------------------------------------------------------
  # #where
  # -------------------------------------------------------------------------
  describe "#where" do
    it "returns all events when given empty criteria" do
      k1 = Class.new(E11y::Event::Base) do
        contains_pii false
        event_name "ev.where1"
      end
      registry.register(k1)
      expect(registry.where).to include(k1)
    end

    it "filters by :severity" do
      error_ev = Class.new(E11y::Event::Base) do
        contains_pii false
        event_name "ev.error_sev"
        severity :error
      end
      info_ev = Class.new(E11y::Event::Base) do
        contains_pii false
        event_name "ev.info_sev"
        severity :info
      end
      registry.register(error_ev)
      registry.register(info_ev)
      result = registry.where(severity: :error)
      expect(result).to include(error_ev)
      expect(result).not_to include(info_ev)
    end

    it "filters by :version" do
      v1 = Class.new(E11y::Event::Base) do
        contains_pii false
        event_name "ev.ver_filter"
        version 1
      end
      v2 = Class.new(E11y::Event::Base) do
        contains_pii false
        event_name "ev.ver_filter2"
        version 2
      end
      registry.register(v1)
      registry.register(v2)
      result = registry.where(version: 1)
      expect(result).to include(v1)
      expect(result).not_to include(v2)
    end

    it "returns empty array for unknown criteria key" do
      klass = Class.new(E11y::Event::Base) do
        contains_pii false
        event_name "ev.unknown_crit"
      end
      registry.register(klass)
      expect(registry.where(nonexistent_key: "value")).to eq([])
    end
  end

  # -------------------------------------------------------------------------
  # #to_documentation
  # -------------------------------------------------------------------------
  describe "#to_documentation" do
    it "returns an array of hashes" do
      klass = Class.new(E11y::Event::Base) do
        event_name "order.doc"
        contains_pii false
      end
      registry.register(klass)
      docs = registry.to_documentation
      expect(docs).to be_an(Array)
    end

    it "includes :name for each event" do
      klass = Class.new(E11y::Event::Base) do
        event_name "order.doc2"
        contains_pii false
      end
      registry.register(klass)
      docs = registry.to_documentation
      expect(docs.map { |d| d[:name] }).to include("order.doc2")
    end

    it "includes :schema_keys for events with a schema" do
      klass = Class.new(E11y::Event::Base) do
        event_name "ev.schema_keys"
        contains_pii false
        schema do
          required(:order_id).filled(:string)
          optional(:amount).maybe(:float)
        end
      end
      registry.register(klass)
      doc = registry.to_documentation.find { |d| d[:name] == "ev.schema_keys" }
      expect(doc[:schema_keys]).to include("order_id", "amount")
    end

    it "omits nil values (uses compact)" do
      klass = Class.new(E11y::Event::Base) do
        event_name "ev.compact"
        contains_pii false
      end
      registry.register(klass)
      doc = registry.to_documentation.first
      expect(doc.keys).not_to include(:schema_keys)
    end

    it "returns empty array when registry is empty" do
      expect(registry.to_documentation).to eq([])
    end
  end

  # -------------------------------------------------------------------------
  # Thread safety
  # -------------------------------------------------------------------------
  describe "thread safety" do
    it "handles concurrent registrations without errors" do
      threads = Array.new(20) do |i|
        Thread.new do
          klass = Class.new(E11y::Event::Base) { contains_pii false }
          # Use the setter so @event_name_explicit is set, required for registration guard
          unique_name = "concurrent.ev.#{i}.#{rand(100_000)}"
          klass.event_name(unique_name)
          registry.register(klass)
        end
      end
      threads.each(&:join)
      expect(registry.size).to be >= 1
    end

    it "returns consistent results under concurrent reads" do
      klass = Class.new(E11y::Event::Base) do
        contains_pii false
        event_name "ev.concurrent.read"
      end
      registry.register(klass)

      results = Array.new(10) do
        Thread.new { registry.all_events }
      end.map(&:value)

      expect(results).to all(include(klass))
    end
  end

  # -------------------------------------------------------------------------
  # Auto-registration via E11y::Event::Base.event_name setter
  # -------------------------------------------------------------------------
  describe "auto-registration via E11y::Event::Base#event_name setter" do
    it "auto-registers when event_name DSL is called on a subclass" do
      described_class.size

      klass = Class.new(E11y::Event::Base) do
        event_name "auto.registered.ev.#{rand(100_000)}"
        contains_pii false
      end

      event_n = klass.event_name
      expect(described_class.find(event_n)).to eq(klass)

      # Clean up global registry
      described_class.instance.clear!
    end

    it "does NOT auto-register anonymous classes with no explicit event_name" do
      # Classes that never call event_name(...) with a value should not pollute the global registry.
      size_before = described_class.size
      _anon = Class.new(E11y::Event::Base) do
        contains_pii false
        # No event_name call here
      end
      # AnonymousEvent guard prevents registration
      expect(described_class.size).to eq(size_before)
    end
  end

  # -------------------------------------------------------------------------
  # Singleton behaviour
  # -------------------------------------------------------------------------
  describe "singleton" do
    it "E11y::Registry.instance returns the same object on repeated calls" do
      instance = described_class.instance
      expect(described_class.instance).to be(instance)
    end

    it "E11y.registry returns the Registry instance" do
      expect(E11y.registry).to be(described_class.instance)
    end

    it "reset! replaces the singleton with a fresh instance" do
      original = described_class.instance
      described_class.reset!
      new_instance = described_class.instance
      expect(new_instance).not_to be(original)
      # Restore singleton so other tests are not affected
      described_class.reset!
    end
  end

  # -------------------------------------------------------------------------
  # Class-level delegation
  # -------------------------------------------------------------------------
  describe "class-level delegation to singleton" do
    before { described_class.instance.clear! }
    after  { described_class.instance.clear! }

    it "E11y::Registry.register delegates to instance" do
      klass = Class.new(E11y::Event::Base) do
        contains_pii false
        event_name "delg.register"
      end
      described_class.register(klass)
      expect(described_class.find("delg.register")).to eq(klass)
    end

    it "E11y::Registry.all_events delegates to instance" do
      klass = Class.new(E11y::Event::Base) do
        contains_pii false
        event_name "delg.all_events"
      end
      described_class.register(klass)
      expect(described_class.all_events).to include(klass)
    end

    it "E11y::Registry.size delegates to instance" do
      klass = Class.new(E11y::Event::Base) do
        contains_pii false
        event_name "delg.size"
      end
      described_class.register(klass)
      expect(described_class.size).to be >= 1
    end

    it "E11y::Registry.validate delegates to instance" do
      klass = Class.new(E11y::Event::Base) do
        event_name "delg.validate"
        contains_pii false
        schema { required(:id).filled(:string) }
      end
      described_class.register(klass)
      expect(described_class.validate("delg.validate")).to be(true)
    end

    it "E11y::Registry.where delegates to instance" do
      klass = Class.new(E11y::Event::Base) do
        contains_pii false
        event_name "delg.where"
        severity :warn
      end
      described_class.register(klass)
      expect(described_class.where(severity: :warn)).to include(klass)
    end

    it "E11y::Registry.to_documentation delegates to instance" do
      klass = Class.new(E11y::Event::Base) do
        contains_pii false
        event_name "delg.docs"
      end
      described_class.register(klass)
      docs = described_class.to_documentation
      expect(docs.map { |d| d[:name] }).to include("delg.docs")
    end

    it "E11y::Registry.clear! delegates to instance" do
      klass = Class.new(E11y::Event::Base) do
        contains_pii false
        event_name "delg.clear"
      end
      described_class.register(klass)
      described_class.clear!
      expect(described_class.size).to eq(0)
    end
  end
end
