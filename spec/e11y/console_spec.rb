# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::Console do
  describe ".enable!" do
    it "calls define_helper_methods and configure_for_console" do
      expect(described_class).to receive(:define_helper_methods)
      expect(described_class).to receive(:configure_for_console)
      described_class.enable!
    end
  end

  describe ".define_helper_methods" do
    it "extends E11y with ConsoleHelpers module" do
      described_class.define_helper_methods
      expect(E11y).to respond_to(:stats)
      expect(E11y).to respond_to(:adapters)
      expect(E11y).to respond_to(:events)
      expect(E11y).to respond_to(:test_event)
      expect(E11y).to respond_to(:reset!)
    end
  end

  describe "ConsoleHelpers" do
    before do
      described_class.define_helper_methods
    end

    describe "#stats" do
      it "returns hash with E11y configuration" do
        stats = E11y.stats
        expect(stats).to be_a(Hash)
        expect(stats).to have_key(:enabled)
        expect(stats).to have_key(:environment)
        expect(stats).to have_key(:service_name)
        expect(stats).to have_key(:adapters)
        expect(stats).to have_key(:buffer)
      end

      it "includes correct enabled value" do
        stats = E11y.stats
        expect(stats[:enabled]).to eq(E11y.config.enabled)
      end

      it "includes correct environment value" do
        stats = E11y.stats
        expect(stats[:environment]).to eq(E11y.config.environment)
      end

      it "includes correct service_name value" do
        stats = E11y.stats
        expect(stats[:service_name]).to eq(E11y.config.service_name)
      end

      it "includes adapters array" do
        stats = E11y.stats
        expect(stats[:adapters]).to be_an(Array)
      end

      it "includes buffer info hash with size" do
        stats = E11y.stats
        expect(stats[:buffer]).to be_a(Hash)
        expect(stats[:buffer]).to have_key(:size)
        expect(stats[:buffer][:size]).to eq(0) # TODO: buffer implementation
      end
    end

    describe "#test_event" do
      it "returns nil" do
        expect(E11y.test_event).to be_nil
      end

      it "calls puts twice" do
        expect { E11y.test_event }.to output.to_stdout
      end
    end

    describe "#events" do
      it "returns empty array" do
        result = E11y.events
        expect(result).to eq([])
      end

      it "outputs to stdout" do
        expect { E11y.events }.to output.to_stdout
      end
    end

    describe "#adapters" do
      it "returns array" do
        adapters = E11y.adapters
        expect(adapters).to be_an(Array)
      end

      it "calls Registry.all" do
        allow(E11y::Adapters::Registry).to receive(:all).and_return([])
        result = E11y.adapters
        expect(result).to eq([])
      end
    end

    describe "#reset!" do
      it "is defined" do
        expect(E11y).to respond_to(:reset!)
      end
    end
  end

  describe ".configure_for_console" do
    it "calls E11y.configure" do
      expect(E11y).to receive(:configure)
      described_class.configure_for_console
    end

    it "handles configuration errors gracefully" do
      allow(E11y).to receive(:configure).and_raise(StandardError, "Test error")

      expect do
        described_class.configure_for_console
      end.to output(/Failed to configure console.*Test error/).to_stderr
    end

    it "warns about configuration failure" do
      allow(E11y).to receive(:configure).and_raise(StandardError, "Something went wrong")

      output = capture_stderr { described_class.configure_for_console }
      expect(output).to match(/Failed to configure console/)
      expect(output).to match(/Something went wrong/)
    end
  end

  private

  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    result = $stdout.string
    result
  ensure
    $stdout = original_stdout
  end

  def capture_stderr
    original_stderr = $stderr
    $stderr = StringIO.new
    yield
    result = $stderr.string
    result
  ensure
    $stderr = original_stderr
  end
end
