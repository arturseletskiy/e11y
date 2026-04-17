# spec/integration/notification_adapters_integration_spec.rb
# frozen_string_literal: true

require "rails_helper"
require "webmock/rspec"
require "e11y/store/memory"
require "e11y/adapters/mattermost_adapter"

RSpec.describe "Notification adapters integration", :integration do
  let(:webhook_url) { "https://mattermost.example.com/hooks/inttest" }
  let(:store)       { E11y::Store::Memory.new }

  let(:adapter) do
    E11y::Adapters::MattermostAdapter.new(
      webhook_url: webhook_url,
      store:       store
    )
  end

  let(:event_class) do
    Class.new(E11y::Event::Base) do
      schema { required(:order_id).filled(:string) }
      severity :error
      contains_pii false

      notify do
        alert throttle_window: 1800, fingerprint: [:event_name]
      end
    end
  end

  before do
    WebMock.enable!
    E11y.configure do |config|
      config.register_adapter :mattermost_test, adapter
    end
    event_class.instance_variable_set(:@adapters, [:mattermost_test])
  end

  after do
    WebMock.reset!
    E11y.configuration.adapters.delete(:mattermost_test)
  end

  it "delivers alert on first track, suppresses duplicate" do
    stub = stub_request(:post, webhook_url).to_return(status: 200)

    event_class.track(order_id: "ORD-1")
    event_class.track(order_id: "ORD-2") # same event_name fingerprint → suppressed

    expect(stub).to have_been_requested.once
  end

  it "delivers to different event types independently" do
    # Use explicit event_name on each class so fingerprints differ even for anonymous classes
    event_class.event_name "order.failed"

    event_b = Class.new(E11y::Event::Base) do
      event_name "user.suspended"
      schema { required(:user_id).filled(:string) }
      severity :error
      contains_pii false
      notify { alert throttle_window: 1800, fingerprint: [:event_name] }
    end
    event_b.instance_variable_set(:@adapters, [:mattermost_test])

    stub = stub_request(:post, webhook_url).to_return(status: 200)

    event_class.track(order_id: "ORD-1")
    event_b.track(user_id: "USR-1")

    expect(stub).to have_been_requested.twice
  end
end
