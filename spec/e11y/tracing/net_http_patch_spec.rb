# frozen_string_literal: true

require "spec_helper"
require "net/http"
require "e11y/tracing/net_http_patch"

RSpec.describe E11y::Tracing::NetHTTPPatch do
  before do
    E11y::Current.reset
  end

  after do
    E11y::Current.reset
  end

  # Use a temporary subclass to avoid polluting Net::HTTP globally across examples
  let(:http_subclass) do
    Class.new(Net::HTTP) do
      # Capture headers of requests passed to #request without making real network calls
      def request(_req, _body = nil)
        # Return a minimal response-like object (don't actually connect)
        Net::HTTPResponse.new("1.1", "200", "OK")
      end
    end
  end

  let(:patched_http_class) do
    klass = http_subclass
    klass.prepend(described_class)
    klass
  end

  def build_http_instance
    # Host/port do not matter since we stub #request via the subclass
    patched_http_class.new("example.com", 80)
  end

  def build_get_request(headers = {})
    req = Net::HTTP::Get.new("/path")
    headers.each { |k, v| req[k] = v }
    req
  end

  context "when trace context is set" do
    before do
      E11y::Current.trace_id = "0af7651916cd43dd8448eb211c80319c"
      E11y::Current.span_id  = "00f067aa0ba902b7"
    end

    it "adds traceparent header to the request" do
      http = build_http_instance
      req  = build_get_request
      http.request(req)
      expect(req["traceparent"]).to eq("00-0af7651916cd43dd8448eb211c80319c-00f067aa0ba902b7-01")
    end
  end

  context "when no trace context is set" do
    it "does not add traceparent header" do
      http = build_http_instance
      req  = build_get_request
      http.request(req)
      expect(req["traceparent"]).to be_nil
    end
  end

  context "when traceparent is already present" do
    before do
      E11y::Current.trace_id = "0af7651916cd43dd8448eb211c80319c"
      E11y::Current.span_id  = "00f067aa0ba902b7"
    end

    it "does not override the existing traceparent" do
      existing = "00-existingtraceidddddddddddddddddd-existingspan0000-01"
      http = build_http_instance
      req  = build_get_request("traceparent" => existing)
      http.request(req)
      expect(req["traceparent"]).to eq(existing)
    end
  end

  describe "E11y::Tracing.patch_net_http!" do
    it "prepends NetHTTPPatch into Net::HTTP" do
      E11y::Tracing.patch_net_http!
      expect(Net::HTTP.ancestors).to include(described_class)
    end

    it "is idempotent — calling twice does not double-prepend" do
      E11y::Tracing.patch_net_http!
      E11y::Tracing.patch_net_http!
      patch_count = Net::HTTP.ancestors.count { |a| a == described_class }
      expect(patch_count).to eq(1)
    end
  end
end
