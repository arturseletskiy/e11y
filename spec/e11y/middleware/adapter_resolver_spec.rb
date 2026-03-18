# frozen_string_literal: true

require "spec_helper"
require "e11y/middleware/adapter_resolver"

RSpec.describe E11y::Middleware::AdapterResolver do
  let(:event_data) { { event_name: "test.event", severity: :info, payload: {} } }
  let(:config_double) do
    instance_double(E11y::Configuration, routing_rules: [], fallback_adapters: [:stdout])
  end

  before do
    allow(E11y).to receive(:configuration).and_return(config_double)
  end

  describe ".resolve" do
    context "when event_data has explicit adapters" do
      it "returns symbolized adapter names" do
        event_data[:adapters] = %w[loki sentry]
        expect(described_class.resolve(event_data)).to eq(%i[loki sentry])
      end

      it "handles symbol adapters" do
        event_data[:adapters] = %i[file stdout]
        expect(described_class.resolve(event_data)).to eq(%i[file stdout])
      end
    end

    context "when event_data has no adapters" do
      it "falls back to routing rules" do
        expect(described_class.resolve(event_data)).to eq([:stdout])
      end
    end
  end

  describe ".apply_routing_rules" do
    context "with no routing rules" do
      it "returns fallback adapters from config" do
        expect(described_class.apply_routing_rules(event_data)).to eq([:stdout])
      end

      it "returns [:stdout] when fallback_adapters is nil" do
        allow(config_double).to receive(:fallback_adapters).and_return(nil)
        expect(described_class.apply_routing_rules(event_data)).to eq([:stdout])
      end
    end

    context "with routing rules that match" do
      it "returns the matched adapters (deduplicated)" do
        rule1 = ->(_e) { [:loki] }
        rule2 = ->(_e) { %i[loki sentry] }
        allow(config_double).to receive(:routing_rules).and_return([rule1, rule2])

        expect(described_class.apply_routing_rules(event_data)).to eq(%i[loki sentry])
      end
    end

    context "with routing rules that raise errors" do
      it "logs a warning and continues to next rule" do
        bad_rule = ->(_e) { raise StandardError, "routing error" }
        good_rule = ->(_e) { [:file] }
        allow(config_double).to receive(:routing_rules).and_return([bad_rule, good_rule])

        expect { described_class.apply_routing_rules(event_data) }.to output(/routing error/).to_stderr
        expect(described_class.apply_routing_rules(event_data)).to eq([:file])
      end
    end
  end
end
