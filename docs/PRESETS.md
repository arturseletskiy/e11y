# Presets

> Back to [README](../README.md#documentation)

E11y provides presets for common event types.

## HighValueEvent

For financial transactions and critical business events:

```ruby
class PaymentProcessedEvent < E11y::Event::Base
  include E11y::Presets::HighValueEvent
  
  schema do
    required(:transaction_id).filled(:string)
    required(:amount).filled(:decimal)
  end
end

# Configured with:
# - severity: :success
# - sample_rate: 1.0 (always sampled)
# - adapters: [:logs, :errors_tracker]
# - rate_limit: unlimited
```

## AuditEvent

For compliance and audit trails:

```ruby
class UserDeletedEvent < E11y::Event::Base
  include E11y::Presets::AuditEvent
  
  schema do
    required(:user_id).filled(:string)
    required(:deleted_by).filled(:string)
  end
end

# Configured with:
# - sample_rate: 1.0 (never sampled)
# - rate_limit: unlimited
# Note: Set severity based on event criticality
```

## DebugEvent

For development and troubleshooting:

```ruby
class SlowQueryEvent < E11y::Event::Base
  include E11y::Presets::DebugEvent
  
  schema do
    required(:query).filled(:string)
    required(:duration_ms).filled(:integer)
  end
end

# Configured with:
# - severity: :debug
# - adapters: [:logs]
```
