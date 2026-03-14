# Testing

> Back to [README](../README.md#documentation)

Use the **InMemoryTest** adapter for testing. It extends `InMemory` and overrides `last_event` to skip Rails auto-instrumentation events (`E11y::Events::Rails::*`), so your business events aren't obscured by request lifecycle events.

## Setup

```ruby
# spec/rails_helper.rb or spec/spec_helper.rb
RSpec.configure do |config|
  config.before(:each) do
    E11y.configure do |e11y_config|
      e11y_config.adapters[:test] = E11y::Adapters::InMemoryTest.new
    end
  end

  config.after(:each) do
    E11y.configuration.adapters[:test]&.clear!
  end
end
```

## Test Events

```ruby
RSpec.describe OrdersController do
  let(:test_adapter) { E11y.configuration.adapters[:test] }
  
  it "tracks order creation" do
    post :create, params: { item: "Book", price: 29.99 }
    
    events = test_adapter.events
    expect(events).to include(
      a_hash_including(
        event_name: "OrderCreatedEvent",
        payload: hash_including(item: "Book", price: 29.99)
      )
    )
  end
  
  it "does not track payment for free orders" do
    post :create, params: { item: "Free Book", price: 0 }
    
    payment_events = test_adapter.events.select { |e| e[:event_name] == "PaymentProcessedEvent" }
    expect(payment_events).to be_empty
  end
end
```

## InMemoryTest Adapter API

```ruby
test_adapter = E11y::Adapters::InMemoryTest.new

# Get all events
test_adapter.events  # => Array<Hash>

# Count events
test_adapter.event_count  # => Integer

# Find last event (skips Rails instrumentation events)
test_adapter.last_event  # => Hash

# Clear all events
test_adapter.clear!
```

> **Note:** Use `InMemoryTest` in test suites; use `InMemory` in production configs (e.g. benchmarks).
