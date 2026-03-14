# frozen_string_literal: true

require "spec_helper"
require "time"

RSpec.describe E11y::Adapters::Stdout do
  let(:adapter) { described_class.new }
  let(:event_data) do
    {
      event_name: "test.event",
      severity: :info,
      timestamp: Time.parse("2026-01-18 10:00:00 UTC"),
      payload: { key: "value" },
      trace_id: "trace-123",
      span_id: "span-456"
    }
  end

  describe "#initialize" do
    it "defaults to colorize enabled" do
      expect(adapter.instance_variable_get(:@colorize)).to be true
    end

    it "defaults to pretty_print enabled" do
      expect(adapter.instance_variable_get(:@pretty_print)).to be true
    end

    it "can disable colorization" do
      adapter = described_class.new(colorize: false)
      expect(adapter.instance_variable_get(:@colorize)).to be false
    end

    it "can disable pretty printing" do
      adapter = described_class.new(pretty_print: false)
      expect(adapter.instance_variable_get(:@pretty_print)).to be false
    end

    it "accepts format: :rich for ADR-010 §3 structured output" do
      adapter = described_class.new(format: :rich, colorize: false)
      expect(adapter.instance_variable_get(:@format)).to eq(:rich)
    end
  end

  describe "format: :rich (ADR-010 §3)" do
    let(:adapter) { described_class.new(format: :rich, colorize: false) }

    it "outputs structured format with header, event name, payload" do
      output = nil
      allow($stdout).to receive(:puts) { |arg| output = arg }

      adapter.write(event_data)

      expect(output).to include("test.event")
      expect(output).to include("Payload:")
      expect(output).to include("key: \"value\"")
      expect(output).to include("→")
      expect(output).to match(/\d{2}:\d{2}:\d{2}\.\d{3}\s+INFO/)
    end

    it "includes metadata section when trace_id present" do
      output = nil
      allow($stdout).to receive(:puts) { |arg| output = arg }

      adapter.write(event_data)

      expect(output).to include("Metadata:")
      expect(output).to include("trace_id: trace-123")
      expect(output).to include("span_id: span-456")
    end
  end

  describe "Console alias (ADR-010 F-003)" do
    it "Console equals Stdout" do
      expect(E11y::Adapters::Console).to eq(E11y::Adapters::Stdout)
    end
  end

  describe "#write" do
    it "outputs event to STDOUT" do
      expect { adapter.write(event_data) }.to output(/test\.event/).to_stdout
    end

    it "returns true on success" do
      allow($stdout).to receive(:puts)
      expect(adapter.write(event_data)).to be true
    end

    it "returns false on failure" do
      allow($stdout).to receive(:puts).and_raise(StandardError, "test error")
      expect(adapter.write(event_data)).to be false
    end

    context "with pretty printing enabled" do
      let(:adapter) { described_class.new(pretty_print: true) }

      it "pretty-prints JSON" do
        output = nil
        allow($stdout).to receive(:puts) { |arg| output = arg }

        adapter.write(event_data)

        expect(output).to include("\n")
        expect(output).to include("  ")
      end
    end

    context "with pretty printing disabled" do
      let(:adapter) { described_class.new(pretty_print: false) }

      it "outputs compact JSON" do
        output = nil
        allow($stdout).to receive(:puts) { |arg| output = arg }

        adapter.write(event_data)

        expect(output).not_to include("  ")
      end
    end

    context "with colorization enabled" do
      let(:adapter) { described_class.new(colorize: true) }

      it "colorizes debug events" do
        output = nil
        allow($stdout).to receive(:puts) { |arg| output = arg }

        adapter.write(event_data.merge(severity: :debug))

        expect(output).to start_with("\e[37m")
        expect(output).to end_with("\e[0m")
      end

      it "colorizes info events" do
        output = nil
        allow($stdout).to receive(:puts) { |arg| output = arg }

        adapter.write(event_data.merge(severity: :info))

        expect(output).to start_with("\e[36m")
      end

      it "colorizes success events" do
        output = nil
        allow($stdout).to receive(:puts) { |arg| output = arg }

        adapter.write(event_data.merge(severity: :success))

        expect(output).to start_with("\e[32m")
      end

      it "colorizes warn events" do
        output = nil
        allow($stdout).to receive(:puts) { |arg| output = arg }

        adapter.write(event_data.merge(severity: :warn))

        expect(output).to start_with("\e[33m")
      end

      it "colorizes error events" do
        output = nil
        allow($stdout).to receive(:puts) { |arg| output = arg }

        adapter.write(event_data.merge(severity: :error))

        expect(output).to start_with("\e[31m")
      end

      it "colorizes fatal events" do
        output = nil
        allow($stdout).to receive(:puts) { |arg| output = arg }

        adapter.write(event_data.merge(severity: :fatal))

        expect(output).to start_with("\e[35m")
      end

      it "uses no color for unknown severity" do
        output = nil
        allow($stdout).to receive(:puts) { |arg| output = arg }

        adapter.write(event_data.merge(severity: :unknown))

        # Should have reset code at the end but no color at start
        expect(output).to end_with("\e[0m")
      end
    end

    context "with colorization disabled" do
      let(:adapter) { described_class.new(colorize: false) }

      it "does not add color codes" do
        output = nil
        allow($stdout).to receive(:puts) { |arg| output = arg }

        adapter.write(event_data)

        expect(output).not_to include("\e[")
      end
    end
  end

  describe "#capabilities" do
    it "indicates streaming support" do
      expect(adapter.capabilities[:streaming]).to be true
    end

    it "does not support batching" do
      expect(adapter.capabilities[:batching]).to be false
    end

    it "does not support compression" do
      expect(adapter.capabilities[:compression]).to be false
    end

    it "is not async" do
      expect(adapter.capabilities[:async]).to be false
    end
  end

  describe "#healthy?" do
    it "returns true" do
      expect(adapter).to be_healthy
    end
  end

  describe "#close" do
    it "does not raise error" do
      expect { adapter.close }.not_to raise_error
    end
  end

  describe "ADR-004 compliance" do
    it "inherits from Base" do
      expect(adapter).to be_a(E11y::Adapters::Base)
    end

    it "implements write method" do
      expect(adapter).to respond_to(:write)
    end

    it "implements write_batch method" do
      expect(adapter).to respond_to(:write_batch)
    end

    it "implements healthy? method" do
      expect(adapter).to respond_to(:healthy?)
    end

    it "implements close method" do
      expect(adapter).to respond_to(:close)
    end

    it "implements capabilities method" do
      expect(adapter).to respond_to(:capabilities)
    end
  end
end
