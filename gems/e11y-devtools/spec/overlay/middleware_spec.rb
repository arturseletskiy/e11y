# frozen_string_literal: true

require "spec_helper"
require "rack/test"
require "rack/mock"
require "e11y/devtools/overlay/middleware"

RSpec.describe E11y::Devtools::Overlay::Middleware do
  include Rack::Test::Methods

  let(:html_body) { "<html><body><h1>Hello</h1></body></html>" }
  let(:base_app) do
    ->(env) { [200, { "Content-Type" => "text/html" }, [html_body]] }
  end

  def app = described_class.new(base_app)

  it "injects overlay script before </body>" do
    get "/"
    expect(last_response.body).to include("e11y-overlay")
    expect(last_response.body).to include("</body>")
  end

  it "does not inject into non-HTML responses" do
    json_app = ->(env) { [200, { "Content-Type" => "application/json" }, ['{"ok":true}']] }
    response = described_class.new(json_app).call(Rack::MockRequest.env_for("/"))
    body = response[2].join
    expect(body).not_to include("e11y-overlay")
  end

  it "does not inject into XHR requests" do
    get "/", {}, { "HTTP_X_REQUESTED_WITH" => "XMLHttpRequest" }
    expect(last_response.body).not_to include("e11y-overlay")
  end

  it "does not inject into asset paths" do
    get "/assets/application.js"
    expect(last_response.body).not_to include("e11y-overlay")
  end

  it "preserves Content-Length consistency after injection" do
    get "/"
    content_length = last_response.headers["Content-Length"]
    if content_length
      expect(content_length.to_i).to eq(last_response.body.bytesize)
    end
  end
end
