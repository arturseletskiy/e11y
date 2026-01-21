# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::Adapters::Registry do
  let(:test_adapter) { E11y::Adapters::InMemory.new }
  let(:another_adapter) { E11y::Adapters::Stdout.new }

  after do
    described_class.clear!
  end

  describe ".register" do
    it "registers adapter by name" do
      described_class.register(:test, test_adapter)
      expect(described_class.registered?(:test)).to be true
    end

    it "validates adapter responds to write" do
      invalid_adapter = Object.new

      expect do
        described_class.register(:invalid, invalid_adapter)
      end.to raise_error(ArgumentError, /must respond to #write/)
    end

    it "validates adapter responds to write_batch" do
      partial_adapter = Class.new do
        def write(event_data); end
      end.new

      expect do
        described_class.register(:partial, partial_adapter)
      end.to raise_error(ArgumentError, /must respond to #write_batch/)
    end

    it "validates adapter responds to healthy?" do
      partial_adapter = Class.new do
        def write(event_data); end

        def write_batch(events); end
      end.new

      expect do
        described_class.register(:partial, partial_adapter)
      end.to raise_error(ArgumentError, /must respond to #healthy\?/)
    end

    it "registers cleanup hook for adapter" do
      allow(test_adapter).to receive(:close)
      described_class.register(:test, test_adapter)

      # Manually trigger cleanup (normally at_exit would handle this)
      described_class.clear!

      expect(test_adapter).to have_received(:close).at_least(:once)
    end

    it "allows registering multiple adapters" do
      described_class.register(:test1, test_adapter)
      described_class.register(:test2, another_adapter)

      expect(described_class.names).to include(:test1, :test2)
    end
  end

  describe ".resolve" do
    before do
      described_class.register(:test, test_adapter)
    end

    it "resolves adapter by name" do
      adapter = described_class.resolve(:test)
      expect(adapter).to be(test_adapter)
    end

    it "raises AdapterNotFoundError when adapter not found" do
      expect do
        described_class.resolve(:nonexistent)
      end.to raise_error(E11y::Adapters::Registry::AdapterNotFoundError, /not found: nonexistent/)
    end

    it "includes registered adapter names in error message" do
      described_class.register(:stdout, another_adapter)

      expect do
        described_class.resolve(:unknown)
      end.to raise_error(E11y::Adapters::Registry::AdapterNotFoundError, /Registered: test, stdout/)
    end
  end

  describe ".resolve_all" do
    before do
      described_class.register(:test1, test_adapter)
      described_class.register(:test2, another_adapter)
    end

    it "resolves multiple adapters by names" do
      adapters = described_class.resolve_all(%i[test1 test2])
      expect(adapters).to eq([test_adapter, another_adapter])
    end

    it "raises error if any adapter not found" do
      expect do
        described_class.resolve_all(%i[test1 nonexistent])
      end.to raise_error(E11y::Adapters::Registry::AdapterNotFoundError)
    end

    it "returns empty array for empty names" do
      adapters = described_class.resolve_all([])
      expect(adapters).to eq([])
    end
  end

  describe ".all" do
    it "returns empty array when no adapters registered" do
      expect(described_class.all).to eq([])
    end

    it "returns all registered adapters" do
      described_class.register(:test1, test_adapter)
      described_class.register(:test2, another_adapter)

      adapters = described_class.all
      expect(adapters).to include(test_adapter, another_adapter)
      expect(adapters.size).to eq(2)
    end
  end

  describe ".names" do
    it "returns empty array when no adapters registered" do
      expect(described_class.names).to eq([])
    end

    it "returns all registered adapter names" do
      described_class.register(:test1, test_adapter)
      described_class.register(:test2, another_adapter)

      expect(described_class.names).to match_array(%i[test1 test2])
    end
  end

  describe ".registered?" do
    before do
      described_class.register(:test, test_adapter)
    end

    it "returns true for registered adapter" do
      expect(described_class.registered?(:test)).to be true
    end

    it "returns false for unregistered adapter" do
      expect(described_class.registered?(:nonexistent)).to be false
    end
  end

  describe ".clear!" do
    before do
      described_class.register(:test1, test_adapter)
      described_class.register(:test2, another_adapter)
    end

    it "clears all registered adapters" do
      described_class.clear!
      expect(described_class.names).to be_empty
    end

    it "calls close on all adapters" do
      allow(test_adapter).to receive(:close)
      allow(another_adapter).to receive(:close)

      described_class.clear!

      expect(test_adapter).to have_received(:close)
      expect(another_adapter).to have_received(:close)
    end

    it "can register adapters again after clear" do
      described_class.clear!
      described_class.register(:new, test_adapter)

      expect(described_class.registered?(:new)).to be true
    end
  end

  describe "thread safety" do
    it "handles concurrent registration" do
      threads = 10.times.map do |i|
        Thread.new do
          adapter = E11y::Adapters::InMemory.new
          described_class.register(:"adapter_#{i}", adapter)
        end
      end

      threads.each(&:join)

      expect(described_class.names.size).to eq(10)
    end

    it "handles concurrent resolution" do
      described_class.register(:test, test_adapter)

      threads = 10.times.map do
        Thread.new { described_class.resolve(:test) }
      end

      results = threads.map(&:value)

      expect(results).to all(be(test_adapter))
    end
  end

  describe "ADR-004 compliance" do
    it "follows global registry pattern" do
      described_class.register(:test, test_adapter)

      # Should resolve same instance globally
      adapter1 = described_class.resolve(:test)
      adapter2 = described_class.resolve(:test)

      expect(adapter1).to be(adapter2)
    end

    it "validates adapter contract" do
      valid_adapter = E11y::Adapters::Base.new
      allow(valid_adapter).to receive(:write).and_return(true)

      expect do
        described_class.register(:valid, valid_adapter)
      end.not_to raise_error
    end

    it "provides clear error messages" do
      expect do
        described_class.resolve(:missing)
      end.to raise_error(E11y::Adapters::Registry::AdapterNotFoundError, /Adapter not found: missing/)
    end
  end
end
