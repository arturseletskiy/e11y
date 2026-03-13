# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::Tracing do
  describe ".patch_net_http!" do
    it "prepends E11y::Tracing::NetHTTPPatch into Net::HTTP" do
      described_class.patch_net_http!
      expect(Net::HTTP.ancestors).to include(E11y::Tracing::NetHTTPPatch)
    end

    it "is idempotent — successive calls do not double-prepend" do
      described_class.patch_net_http!
      described_class.patch_net_http!
      count = Net::HTTP.ancestors.count { |a| a == E11y::Tracing::NetHTTPPatch }
      expect(count).to eq(1)
    end

    it "does not raise" do
      expect { described_class.patch_net_http! }.not_to raise_error
    end
  end

  describe ".install_faraday_middleware!" do
    before do
      skip "Faraday not available" unless defined?(Faraday)
    end

    it "registers :e11y_tracing middleware with Faraday::Request" do
      described_class.install_faraday_middleware!
      expect(Faraday::Request.lookup_middleware(:e11y_tracing)).to eq(E11y::Tracing::FaradayMiddleware)
    end

    it "is idempotent — successive calls do not raise" do
      described_class.install_faraday_middleware!
      expect { described_class.install_faraday_middleware! }.not_to raise_error
    end

    it "makes the middleware usable in a Faraday connection" do
      described_class.install_faraday_middleware!
      expect do
        Faraday.new { |f| f.request :e11y_tracing }
      end.not_to raise_error
    end
  end
end
