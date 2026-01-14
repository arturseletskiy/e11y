# UC-022: Event Registry & Introspection

**Status:** Developer Experience Feature (v1.1+)  
**Complexity:** Low  
**Setup Time:** 5-10 minutes  
**Target Users:** Backend Developers, QA Engineers, Documentation Writers

---

## 📋 Overview

### Problem Statement

**Current Pain Points:**

1. **No catalog of events**
   - What events exist in the system?
   - Need to grep codebase to find event classes
   - Hard to document all events

2. **No runtime introspection**
   - Can't list all registered events at runtime
   - Can't find event class by name
   - Can't inspect event schema programmatically

3. **Hard to build tooling**
   - Can't build event explorer UI (no registry)
   - Can't auto-generate documentation
   - Can't validate that all events are documented

### E11y Solution

**Event Registry with Full Introspection:**

- Automatic registration of all event classes
- Query registry by event name, version, adapter
- Schema introspection (fields, types, validations)
- Build developer tools (event explorer, documentation generator)

**Result:** Full visibility into all events in the system.

---

## 🎯 Use Case Scenarios

### Scenario 1: List All Events

**Problem:** Need to document all events in the system.

```ruby
# Without registry (MANUAL GREP):
$ grep -r "class.*< E11y::Event::Base" app/events/
# → Manual, error-prone, outdated

# With registry (AUTOMATIC):
E11y::Registry.all_events
# => [
#   Events::OrderCreated,
#   Events::OrderPaid,
#   Events::UserSignup,
#   Events::PaymentFailed,
#   ...
# ]

# Generate documentation:
E11y::Registry.all_events.each do |event_class|
  puts "## #{event_class.event_name}"
  puts "Version: #{event_class.version}"
  puts "Schema: #{event_class.schema_definition}"
end
```

---

### Scenario 2: Find Event by Name

**Problem:** Need to find event class for dynamic event tracking.

```ruby
# Without registry (STRING EVAL - DANGEROUS!):
event_name = 'order.created'
event_class = eval("Events::#{event_name.classify}")  # ❌ DANGEROUS!

# With registry (SAFE):
event_class = E11y::Registry.find('order.created')
# => Events::OrderCreated

# Dynamic tracking:
event_class.track(order_id: '123', amount: 99.99)
```

---

### Scenario 3: Schema Introspection

**Problem:** Need to generate API documentation showing event schemas.

```ruby
# Introspect event schema
event = Events::OrderPaid

event.event_name
# => "order.paid"

event.version
# => 2

event.schema_definition
# => {
#   order_id: { type: :string, required: true },
#   amount: { type: :decimal, required: true },
#   currency: { type: :string, required: true }
# }

event.adapters
# => [:loki, :sentry, :file]

event.severity_level
# => :info

# Generate OpenAPI spec:
{
  "event.name": event.event_name,
  "properties": event.schema_definition.transform_values { |v| v[:type] }
}
```

---

### Scenario 4: Event Explorer UI

**Problem:** Developers need to see all events and test them.

```ruby
# Rails controller for event explorer
class EventExplorerController < ApplicationController
  def index
    @events = E11y::Registry.all_events.map do |event_class|
      {
        name: event_class.event_name,
        version: event_class.version,
        schema: event_class.schema_definition,
        adapters: event_class.adapters,
        examples: event_class.example_payloads
      }
    end
  end
  
  def show
    @event = E11y::Registry.find(params[:name])
    
    # Show details:
    # - Schema
    # - Recent tracked events
    # - Metrics (how many times tracked)
  end
  
  def test
    event_class = E11y::Registry.find(params[:name])
    payload = JSON.parse(params[:payload])
    
    # Test tracking
    event_class.track(**payload)
    
    flash[:success] = "Event tracked successfully!"
  end
end
```

---

## 🏗️ Architecture

### Registry Structure

```
┌─────────────────────────────────────────────────────────────────┐
│ E11y::Registry (Global Singleton)                               │
│                                                                  │
│  @events = {                                                     │
│    'order.created' => {                                          │
│      v1: Events::OrderCreatedV1,                                 │
│      v2: Events::OrderCreatedV2 (current)                        │
│    },                                                            │
│    'order.paid' => {                                             │
│      v1: Events::OrderPaidV1,                                    │
│      v2: Events::OrderPaidV2 (current)                           │
│    },                                                            │
│    'user.signup' => {                                            │
│      v1: Events::UserSignup (current)                            │
│    }                                                             │
│  }                                                               │
│                                                                  │
│  Indexes:                                                        │
│  - by_name: 'order.created' → Events::OrderCreatedV2            │
│  - by_adapter: :sentry → [Events::PaymentFailed, ...]           │
│  - by_severity: :error → [Events::SystemError, ...]             │
│  - by_version: 2 → [Events::OrderCreatedV2, ...]                │
└─────────────────────────────────────────────────────────────────┘
```

### Auto-Registration

```ruby
# Event classes automatically register on load
module Events
  class OrderCreated < E11y::Event::Base
    # On class definition:
    # 1. E11y::Registry.register(self)
    # 2. Store: event_name, version, schema, adapters
  end
end

# Behind the scenes:
class E11y::Event::Base
  def self.inherited(subclass)
    super
    E11y::Registry.register(subclass)  # Auto-register
  end
end
```

---

## 🔧 Configuration

### Basic Setup

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.registry do
    enabled true
    
    # Eager load event classes (for registry)
    eager_load true
    eager_load_paths [
      Rails.root.join('app', 'events')
    ]
    
    # Registry features
    enable_introspection true
    enable_event_explorer true  # Web UI at /e11y/events
  end
end
```

---

## 📝 Registry API

> **Implementation:** See [ADR-010 Section 5: Event Registry](../ADR-010-developer-experience.md#5-event-registry) for full registry architecture, including event discovery API, introspection, version tracking, and dynamic dispatch.

### Query Events

```ruby
# === List All Events ===
E11y::Registry.all_events
# => [Events::OrderCreated, Events::OrderPaid, ...]

E11y::Registry.count
# => 42

# === Find by Name ===
E11y::Registry.find('order.created')
# => Events::OrderCreated (latest version)

E11y::Registry.find('order.created', version: 1)
# => Events::OrderCreatedV1

# === Find by Criteria ===
E11y::Registry.where(adapter: :sentry)
# => [Events::PaymentFailed, Events::SystemError, ...]

E11y::Registry.where(severity: :error)
# => [Events::PaymentFailed, ...]

E11y::Registry.where(version: 2)
# => [Events::OrderCreatedV2, Events::OrderPaidV2, ...]

# === Search ===
E11y::Registry.search('payment')
# => [Events::PaymentProcessed, Events::PaymentFailed, ...]

# === Filtering ===
E11y::Registry.filter do |event_class|
  event_class.adapters.include?(:sentry) &&
  event_class.severity_level == :error
end
# => [Events::PaymentFailed, Events::SystemError]
```

### Introspection API

```ruby
event = Events::OrderPaid

# === Basic Info ===
event.event_name
# => "order.paid"

event.version
# => 2

event.default_version?
# => true

event.deprecated?
# => false

# === Schema ===
event.schema_definition
# => {
#   order_id: { type: :string, required: true },
#   amount: { type: :decimal, required: true },
#   currency: { type: :string, required: true }
# }

event.required_fields
# => [:order_id, :amount, :currency]

event.optional_fields
# => []

event.field_type(:amount)
# => :decimal

# === Adapters ===
event.adapters
# => [:loki, :sentry]

event.uses_adapter?(:sentry)
# => true

# === Severity ===
event.severity_level
# => :info

event.track_success?
# => false

# === Examples ===
event.example_payloads
# => [
#   { order_id: '123', amount: 99.99, currency: 'USD' },
#   { order_id: '456', amount: 49.99, currency: 'EUR' }
# ]
```

### Statistics

```ruby
# === Registry Stats ===
E11y::Registry.stats
# => {
#   total_events: 42,
#   by_adapter: {
#     loki: 42,
#     sentry: 15,
#     file: 42
#   },
#   by_severity: {
#     debug: 10,
#     info: 20,
#     warn: 8,
#     error: 4
#   },
#   by_version: {
#     1: 30,
#     2: 12
#   },
#   deprecated: 5
# }

# === Event Usage Stats (requires tracking) ===
E11y::Registry.usage_stats
# => {
#   'order.created' => { total: 1000, last_24h: 100 },
#   'order.paid' => { total: 800, last_24h: 80 },
#   ...
# }
```

---

## 💡 Developer Tools

### 1. Event Explorer Web UI

```ruby
# Available at: http://localhost:3000/e11y/events

# Features:
# - List all events
# - Search/filter events
# - View event schema
# - Test event tracking
# - View recent tracked events
# - View event metrics

# Enable in config:
E11y.configure do |config|
  config.development.event_explorer do
    enabled true
    mount_path '/e11y/events'
    
    # Authentication (production)
    authenticate_with do |username, password|
      username == ENV['E11Y_USER'] && password == ENV['E11Y_PASS']
    end
  end
end
```

### 2. Documentation Generator

```ruby
# Rake task: generate event documentation
# lib/tasks/e11y_docs.rake
namespace :e11y do
  desc 'Generate event documentation'
  task docs: :environment do
    output = StringIO.new
    
    output.puts "# E11y Events Documentation"
    output.puts
    output.puts "Total events: #{E11y::Registry.count}"
    output.puts
    
    E11y::Registry.all_events.each do |event_class|
      output.puts "## #{event_class.event_name}"
      output.puts
      output.puts "**Version:** #{event_class.version}"
      output.puts "**Severity:** #{event_class.severity_level}"
      output.puts "**Adapters:** #{event_class.adapters.join(', ')}"
      output.puts
      output.puts "### Schema"
      output.puts
      output.puts "| Field | Type | Required |"
      output.puts "|-------|------|----------|"
      
      event_class.schema_definition.each do |field, opts|
        output.puts "| #{field} | #{opts[:type]} | #{opts[:required] ? 'Yes' : 'No'} |"
      end
      
      output.puts
      output.puts "### Example"
      output.puts
      output.puts "```ruby"
      output.puts "#{event_class.name}.track("
      event_class.example_payloads.first.each do |key, value|
        output.puts "  #{key}: #{value.inspect},"
      end
      output.puts ")"
      output.puts "```"
      output.puts
    end
    
    File.write('docs/EVENTS.md', output.string)
    puts "✅ Documentation generated: docs/EVENTS.md"
  end
end

# Run:
# $ rake e11y:docs
```

### 3. Event Validator

```ruby
# Validate all events are documented
# lib/tasks/e11y_validate.rake
namespace :e11y do
  desc 'Validate all events'
  task validate: :environment do
    errors = []
    
    E11y::Registry.all_events.each do |event_class|
      # Check: has example payload
      if event_class.example_payloads.empty?
        errors << "#{event_class.name} has no example payloads"
      end
      
      # Check: has documentation comment
      unless event_class.documented?
        errors << "#{event_class.name} has no documentation"
      end
      
      # Check: deprecated events have deprecation_date
      if event_class.deprecated? && event_class.deprecation_date.nil?
        errors << "#{event_class.name} is deprecated but no deprecation_date"
      end
    end
    
    if errors.any?
      puts "❌ Found #{errors.size} issues:"
      errors.each { |err| puts "  - #{err}" }
      exit 1
    else
      puts "✅ All events valid"
    end
  end
end

# Run in CI:
# $ rake e11y:validate
```

### 4. OpenAPI Generator

```ruby
# Generate OpenAPI spec for events
namespace :e11y do
  desc 'Generate OpenAPI spec'
  task openapi: :environment do
    spec = {
      openapi: '3.0.0',
      info: {
        title: 'E11y Events API',
        version: '1.0.0'
      },
      paths: {}
    }
    
    E11y::Registry.all_events.each do |event_class|
      spec[:paths]["/events/#{event_class.event_name}"] = {
        post: {
          summary: "Track #{event_class.event_name} event",
          requestBody: {
            content: {
              'application/json': {
                schema: {
                  type: 'object',
                  properties: event_class.schema_definition.transform_values { |v|
                    { type: v[:type].to_s }
                  },
                  required: event_class.required_fields.map(&:to_s)
                }
              }
            }
          }
        }
      }
    end
    
    File.write('docs/openapi.json', JSON.pretty_generate(spec))
    puts "✅ OpenAPI spec generated: docs/openapi.json"
  end
end
```

---

## 🧪 Testing

### RSpec Examples

```ruby
RSpec.describe E11y::Registry do
  describe '.all_events' do
    it 'returns all registered events' do
      events = E11y::Registry.all_events
      
      expect(events).to include(Events::OrderCreated)
      expect(events).to include(Events::OrderPaid)
      expect(events.size).to be > 0
    end
  end
  
  describe '.find' do
    it 'finds event by name' do
      event = E11y::Registry.find('order.created')
      
      expect(event).to eq(Events::OrderCreated)
    end
    
    it 'finds event by name and version' do
      event = E11y::Registry.find('order.created', version: 1)
      
      expect(event).to eq(Events::OrderCreatedV1)
    end
    
    it 'returns nil for unknown event' do
      event = E11y::Registry.find('unknown.event')
      
      expect(event).to be_nil
    end
  end
  
  describe '.where' do
    it 'filters by adapter' do
      events = E11y::Registry.where(adapter: :sentry)
      
      expect(events).to all(satisfy { |e| e.adapters.include?(:sentry) })
    end
    
    it 'filters by severity' do
      events = E11y::Registry.where(severity: :error)
      
      expect(events).to all(have_attributes(severity_level: :error))
    end
  end
  
  describe 'introspection' do
    let(:event) { Events::OrderPaid }
    
    it 'exposes event metadata' do
      expect(event.event_name).to eq('order.paid')
      expect(event.version).to eq(2)
      expect(event.adapters).to include(:loki, :sentry)
    end
    
    it 'exposes schema' do
      schema = event.schema_definition
      
      expect(schema).to include(
        order_id: { type: :string, required: true },
        amount: { type: :decimal, required: true }
      )
    end
  end
end
```

---

## 🔗 Related Use Cases

- **[UC-017: Local Development](./UC-017-local-development.md)** - Event Explorer UI
- **[UC-020: Event Versioning](./UC-020-event-versioning.md)** - Version registry
- **[UC-002: Business Event Tracking](./UC-002-business-event-tracking.md)** - Event definitions

---

## 🚀 Quick Start Checklist

- [ ] Enable registry in config
- [ ] Enable eager loading of event classes
- [ ] Access registry: `E11y::Registry.all_events`
- [ ] Enable event explorer UI (development only)
- [ ] Set up documentation generator rake task
- [ ] Run validation in CI: `rake e11y:validate`

---

**Status:** ✅ Developer Experience Feature  
**Priority:** Nice-to-Have (v1.1+)  
**Complexity:** Low
