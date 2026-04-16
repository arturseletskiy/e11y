# spec/e11y/adapters/notification_base_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "e11y/store/memory"
require "e11y/adapters/notification_base"

RSpec.describe E11y::Adapters::NotificationBase do
  # Minimal concrete subclass
  let(:concrete_class) do
    Class.new(described_class) do
      def adapter_id_source = "test:concrete"
      def format_alert(event_data) = "alert: #{event_data[:event_name]}"
      def format_digest(**) = "digest"
      def deliver_alert(_event_data) = true # rubocop:disable Naming/PredicateMethod
      def deliver_digest(**) = true # rubocop:disable Naming/PredicateMethod
    end
  end

  let(:store) { E11y::Store::Memory.new }

  describe "#initialize" do
    it "raises ArgumentError when :store absent" do
      expect { concrete_class.new({}) }.to raise_error(
        ArgumentError, /requires :store/
      )
    end

    it "accepts valid store" do
      expect { concrete_class.new(store: store) }.not_to raise_error
    end

    it "accepts max_event_types option" do
      adapter = concrete_class.new(store: store, max_event_types: 5)
      expect(adapter.instance_variable_get(:@max_event_types)).to eq(5)
    end

    it "defaults max_event_types to 20" do
      adapter = concrete_class.new(store: store)
      expect(adapter.instance_variable_get(:@max_event_types)).to eq(20)
    end
  end

  describe "#write delegates to Throttleable" do
    it "returns true for event without notify config" do
      adapter = concrete_class.new(store: store)
      expect(adapter.write(event_name: "foo", severity: :info)).to be(true)
    end
  end

  describe "capabilities" do
    it "reports correct capabilities" do
      adapter = concrete_class.new(store: store)
      caps = adapter.capabilities
      expect(caps[:batching]).to be(false)
      expect(caps[:async]).to be(false)
    end
  end
end
