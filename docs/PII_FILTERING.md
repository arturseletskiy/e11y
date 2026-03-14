# PII Filtering

> Back to [README](../README.md#documentation)

E11y provides PII filtering capabilities for sensitive data.

## Rails Integration

E11y can respect `Rails.application.config.filter_parameters` when configured:

```ruby
# config/application.rb
config.filter_parameters += [:password, :email, :ssn, :credit_card]

# E11y will filter these fields when PII filtering middleware is enabled
```

## Explicit PII Strategies

Configure PII filtering per event:

```ruby
class PaymentEvent < E11y::Event::Base
  contains_pii true
  
  pii_filtering do
    masks :card_number     # Replace with "[FILTERED]"
    hashes :user_email     # SHA256 hash (searchable)
    allows :amount         # No filtering
  end
end
```

Available strategies:

- `masks` - Replace with "[FILTERED]"
- `hashes` - SHA256 hash (preserves searchability)
- `partials` - Show first/last characters
- `redacts` - Remove completely
- `allows` - No filtering
