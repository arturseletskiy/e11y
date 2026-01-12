# UC-007: PII Filtering (Rails-Compatible)

**Status:** MVP Feature (Critical for Production)  
**Complexity:** Intermediate  
**Setup Time:** 20-30 minutes  
**Target Users:** All developers, Security teams, Compliance teams

---

## 📋 Overview

### Problem Statement

**Current Approach (Configuration Duplication):**
```ruby
# config/application.rb
# Rails already has PII filtering
config.filter_parameters += [:password, :email, :ssn, :credit_card]

# config/initializers/e11y.rb
# Do we need to duplicate for E11y?
E11y.configure do |config|
  config.pii_filter do
    mask_fields :password, :email, :ssn, :credit_card  # ← Duplication! 😞
  end
end

# Problems:
# - Configuration duplication
# - Easy to forget updating both places
# - Inconsistency risk
# - More maintenance burden
```

### E11y Solution

**Rails-compatible PII filtering (zero config):**
```ruby
# config/application.rb
# Configure ONCE in Rails (standard way)
config.filter_parameters += [:password, :email, :ssn, :credit_card]

# config/initializers/e11y.rb
E11y.configure do |config|
  # NO PII CONFIGURATION NEEDED!
  # E11y automatically uses Rails.filter_parameters ✨
end

# Track event with PII
Events::UserRegistered.track(
  email: 'user@example.com',    # → Automatically filtered to '[FILTERED]'
  password: 'secret123',         # → Automatically filtered to '[FILTERED]'
  name: 'John Doe'               # → NOT filtered (not in filter_parameters)
)

# Result in logs/adapters:
# {
#   event_name: 'user.registered',
#   payload: {
#     email: '[FILTERED]',      # ← Automatically masked
#     password: '[FILTERED]',   # ← Automatically masked
#     name: 'John Doe'          # ← Not filtered
#   }
# }
```

---

## 🎯 Features

### 1. Automatic Rails Integration (Zero Config)

**Default behavior:**
```ruby
# config/application.rb (Rails standard)
config.filter_parameters += [:password, :email, :ssn]

# E11y automatically respects this!
Events::UserCreated.track(
  user_id: '123',
  email: 'user@example.com',
  password: 'secret'
)

# Logged as:
# {
#   user_id: '123',              # ← Not filtered
#   email: '[FILTERED]',         # ← Filtered by Rails config
#   password: '[FILTERED]'       # ← Filtered by Rails config
# }
```

---

### 2. Extended Configuration (Optional)

**Add more filters beyond Rails:**
```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.pii_filter do
    # 1. USE RAILS FILTERS (default: true)
    use_rails_filter_parameters true
    
    # 2. ADD MORE FIELDS (Rails-compatible syntax)
    filter_parameters :api_key, :token, :auth_token, :secret_key
    
    # 3. REGEX FILTERS (like Rails)
    filter_parameters /token/i       # Matches: auth_token, api_token, etc.
    filter_parameters /secret/i      # Matches: client_secret, api_secret, etc.
    
    # 4. WHITELIST (don't filter these, even if in Rails.filter_parameters)
    allow_parameters :user_id, :order_id, :transaction_id
    
    # 5. CUSTOM REPLACEMENT (default: '[FILTERED]')
    replacement '[REDACTED]'
    
    # 6. KEEP PARTIAL DATA (for debugging)
    keep_partial_data true  # 'em***@ex***' instead of '[FILTERED]'
  end
end
```

---

### 3. Pattern-Based Filtering (Beyond Rails)

**Advanced regex patterns for content scanning:**
```ruby
E11y.configure do |config|
  config.pii_filter do
    # EMAIL ADDRESSES (scan content, not just keys)
    filter_pattern /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i,
                   replacement: '[EMAIL]'
    
    # CREDIT CARDS
    filter_pattern /\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b/,
                   replacement: '[CARD]'
    
    # SOCIAL SECURITY NUMBERS
    filter_pattern /\b\d{3}-\d{2}-\d{4}\b/,
                   replacement: '[SSN]'
    
    # PHONE NUMBERS (US/International)
    filter_pattern /\b(\+\d{1,2}\s?)?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}\b/,
                   replacement: '[PHONE]'
    
    # IP ADDRESSES
    filter_pattern /\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/,
                   replacement: '[IP]'
    
    # API KEYS (common formats)
    filter_pattern /[A-Za-z0-9_]{32,}/,  # Long alphanumeric strings
                   replacement: '[API_KEY]'
  end
end

# Usage:
Events::EmailSent.track(
  subject: 'Hello user@example.com!',  # → 'Hello [EMAIL]!'
  body: 'Your card 4111-1111-1111-1111 was charged'  # → 'Your card [CARD] was charged'
)
```

---

### 4. Custom Filter Functions

**Full control for complex scenarios:**
```ruby
E11y.configure do |config|
  config.pii_filter do
    # Custom filter #1: Mask URLs with secrets
    filter do |key, value|
      if value.is_a?(String) && value.include?('?')
        # Mask query parameters in URLs
        value.gsub(/([?&])(api_key|token|secret)=[^&]+/, '\1\2=[FILTERED]')
      else
        value
      end
    end
    
    # Custom filter #2: Mask long strings (likely secrets)
    filter do |key, value|
      if value.is_a?(String) && value.length > 64 && value.match?(/^[A-Za-z0-9_-]+$/)
        '[LONG_TOKEN]'
      else
        value
      end
    end
    
    # Custom filter #3: Conditional filtering
    filter do |key, value|
      # Only filter emails in production
      if Rails.env.production? && value.to_s.match?(/@/)
        value.gsub(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i, '[EMAIL]')
      else
        value  # Don't filter in dev/test
      end
    end
  end
end
```

---

### 5. Deep Scanning (Nested Data)

**Scan nested hashes and arrays:**
```ruby
E11y.configure do |config|
  config.pii_filter do
    deep_scan true  # Default: enabled
    
    # Maximum depth (prevent infinite recursion)
    max_depth 10
  end
end

# Deep scanning in action:
Events::OrderPlaced.track(
  order_id: '123',
  user: {
    name: 'John Doe',
    contact: {
      email: 'john@example.com',    # ← Nested deep, still filtered!
      phone: '+1-555-123-4567'
    },
    billing: {
      card: {
        number: '4111-1111-1111-1111',  # ← 3 levels deep, still filtered!
        cvv: '123'
      }
    }
  },
  items: [
    { name: 'Product 1', notes: 'Ship to user@example.com' }  # ← In array, still filtered!
  ]
)

# Result:
# {
#   order_id: '123',
#   user: {
#     name: 'John Doe',
#     contact: {
#       email: '[FILTERED]',          # ← Filtered
#       phone: '[PHONE]'               # ← Filtered by pattern
#     },
#     billing: {
#       card: {
#         number: '[CARD]',            # ← Filtered by pattern
#         cvv: '[FILTERED]'            # ← Filtered by key
#       }
#     }
#   },
#   items: [
#     { name: 'Product 1', notes: 'Ship to [EMAIL]' }  # ← Content filtered
#   ]
# }
```

---

### 6. Sampling for Debugging

**Log some filtered values for verification:**
```ruby
E11y.configure do |config|
  config.pii_filter do
    # Sample 1% of filtered values (for debugging)
    sample_filtered_values 0.01
    
    # Log destination
    sample_logger Rails.logger  # Or custom logger
  end
end

# When filtering happens, 1% of time you'll see in logs:
# [E11y DEBUG] PII filtered: email = "user@examp..." → [FILTERED]
# [E11y DEBUG] PII filtered: password = "secre..." → [FILTERED]
```

---

## 💻 Implementation Examples

### Example 1: User Registration

```ruby
# app/controllers/registrations_controller.rb
class RegistrationsController < ApplicationController
  def create
    user = User.new(registration_params)
    
    if user.save
      # Track registration (PII automatically filtered)
      Events::UserRegistered.track(
        user_id: user.id,
        email: user.email,                # ← Filtered
        password: params[:password],      # ← Filtered
        referral_code: params[:referral], # ← Not filtered
        ip_address: request.remote_ip     # ← Filtered by pattern
      )
      
      render json: { status: 'ok' }
    else
      # Track failure (errors may contain PII)
      Events::UserRegistrationFailed.track(
        email: params[:email],      # ← Filtered
        errors: user.errors.full_messages,
        severity: :error
      )
      
      render json: { errors: user.errors }, status: :unprocessable_entity
    end
  end
end

# Logged events (all PII filtered):
# {
#   event_name: 'user.registered',
#   payload: {
#     user_id: '123',
#     email: '[FILTERED]',
#     password: '[FILTERED]',
#     referral_code: 'FRIEND10',
#     ip_address: '[IP]'
#   }
# }
```

---

### Example 2: Payment Processing

```ruby
# app/services/process_payment_service.rb
class ProcessPaymentService
  def call(order, card_params)
    # Track payment attempt (card details filtered)
    Events::PaymentAttempted.track(
      order_id: order.id,
      amount: order.total,
      card_number: card_params[:number],     # ← Filtered by pattern
      card_cvv: card_params[:cvv],           # ← Filtered by key
      card_holder: card_params[:name],       # ← Not filtered (name != PII)
      billing_address: card_params[:address] # ← Deep scanned
    )
    
    begin
      result = PaymentGateway.charge(
        amount: order.total,
        card: card_params
      )
      
      # Track success
      Events::PaymentSucceeded.track(
        order_id: order.id,
        transaction_id: result.id,
        card_last4: card_params[:number][-4..-1],  # Last 4 digits OK
        severity: :success
      )
      
    rescue PaymentGateway::Error => e
      # Track failure (error message may contain PII)
      Events::PaymentFailed.track(
        order_id: order.id,
        error_message: e.message,        # ← Content filtered
        error_code: e.code,
        severity: :error
      )
      
      raise
    end
  end
end
```

---

### Example 3: Support Ticket Creation

```ruby
# app/controllers/support_tickets_controller.rb
class SupportTicketsController < ApplicationController
  def create
    ticket = SupportTicket.create!(ticket_params)
    
    # Track ticket creation (description may contain PII)
    Events::SupportTicketCreated.track(
      ticket_id: ticket.id,
      subject: ticket.subject,
      description: ticket.description,  # ← Content scanned for emails, phones, etc.
      category: ticket.category,
      attachments: ticket.attachments.map do |file|
        {
          filename: file.filename,
          size: file.size,
          url: file.url                   # ← URLs with query strings filtered
        }
      end
    )
    
    render json: ticket
  end
end

# If description contains PII:
# "Please help! My email is john@example.com and phone is 555-1234"
#
# Logged as:
# "Please help! My email is [EMAIL] and phone is [PHONE]"
```

---

## 🔧 Configuration API

### Full Configuration Example

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.pii_filter do
    # === BASIC CONFIGURATION ===
    
    # Use Rails filter_parameters (default: true)
    use_rails_filter_parameters true
    
    # Add more filters (Rails-compatible syntax)
    filter_parameters :api_key, :token, :auth_token, :secret_key
    filter_parameters /token/i, /secret/i, /key/i
    
    # Whitelist (don't filter these)
    allow_parameters :user_id, :order_id, :transaction_id, :session_id
    
    # === PATTERN-BASED FILTERING ===
    
    # Email addresses
    filter_pattern /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i,
                   replacement: '[EMAIL]'
    
    # Credit cards
    filter_pattern /\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b/,
                   replacement: '[CARD]'
    
    # SSN
    filter_pattern /\b\d{3}-\d{2}-\d{4}\b/,
                   replacement: '[SSN]'
    
    # Phone numbers
    filter_pattern /\b(\+\d{1,2}\s?)?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}\b/,
                   replacement: '[PHONE]'
    
    # IP addresses
    filter_pattern /\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/,
                   replacement: '[IP]'
    
    # === CUSTOM FILTERS ===
    
    # Mask query parameters in URLs
    filter do |key, value|
      if value.is_a?(String) && value.include?('?')
        value.gsub(/([?&])(api_key|token|secret)=[^&]+/, '\1\2=[FILTERED]')
      else
        value
      end
    end
    
    # === BEHAVIOR ===
    
    # Deep scan nested data (default: true)
    deep_scan true
    max_depth 10
    
    # Replacement strategy
    replacement '[FILTERED]'
    keep_partial_data true  # Show 'em***@ex***' instead of '[FILTERED]'
    
    # Sampling (for debugging)
    sample_filtered_values 0.01  # 1%
    sample_logger Rails.logger
    
    # Performance
    enabled true                  # Can disable in dev/test
    cache_compiled_patterns true  # Compile regex once
  end
end
```

---

## 📊 Monitoring

### Self-Monitoring Metrics

```ruby
# Track PII filtering effectiveness
E11y.configure do |config|
  config.self_monitoring do
    # Count filtered fields
    counter :pii_fields_filtered_total,
            tags: [:field_name, :filter_type]
    
    # Count pattern matches
    counter :pii_patterns_matched_total,
            tags: [:pattern_name]
    
    # Track performance impact
    histogram :pii_filter_duration_ms,
              tags: [:event_name],
              buckets: [0.1, 0.5, 1.0, 5.0, 10.0]
  end
end

# Prometheus queries:
# - How many emails filtered per day?
#   sum(increase(e11y_pii_fields_filtered_total{field_name="email"}[1d]))
#
# - Which events have most PII?
#   topk(10, sum by (event_name) (e11y_pii_fields_filtered_total))
#
# - Performance impact?
#   histogram_quantile(0.99, e11y_pii_filter_duration_ms_bucket)
```

---

## 🧪 Testing

### RSpec Examples

```ruby
# spec/e11y/pii_filtering_spec.rb
RSpec.describe 'E11y PII Filtering' do
  before do
    # Configure Rails filters
    Rails.application.config.filter_parameters += [:email, :password]
    
    E11y.configure do |config|
      config.pii_filter do
        use_rails_filter_parameters true
        filter_pattern /\d{4}-\d{4}-\d{4}-\d{4}/, replacement: '[CARD]'
      end
    end
  end
  
  it 'filters Rails filter_parameters' do
    Events::UserCreated.track(
      email: 'user@example.com',
      password: 'secret123'
    )
    
    event = E11y::Buffer.pop
    expect(event[:payload][:email]).to eq('[FILTERED]')
    expect(event[:payload][:password]).to eq('[FILTERED]')
  end
  
  it 'filters by pattern (credit cards)' do
    Events::PaymentProcessed.track(
      card_number: '4111-1111-1111-1111',
      amount: 99.99
    )
    
    event = E11y::Buffer.pop
    expect(event[:payload][:card_number]).to eq('[CARD]')
    expect(event[:payload][:amount]).to eq(99.99)  # Not filtered
  end
  
  it 'deep scans nested data' do
    Events::OrderPlaced.track(
      order_id: '123',
      user: {
        contact: {
          email: 'nested@example.com'
        }
      }
    )
    
    event = E11y::Buffer.pop
    expect(event[:payload][:user][:contact][:email]).to eq('[FILTERED]')
  end
  
  it 'respects whitelist' do
    E11y.configure do |config|
      config.pii_filter do
        allow_parameters :user_id
      end
    end
    
    # Even if 'user_id' is in Rails.filter_parameters
    Rails.application.config.filter_parameters += [:user_id]
    
    Events::UserAction.track(user_id: '123')
    
    event = E11y::Buffer.pop
    expect(event[:payload][:user_id]).to eq('123')  # NOT filtered
  end
end
```

---

## 💡 Best Practices

### ✅ DO

**1. Use Rails filter_parameters as single source of truth**
```ruby
# ✅ GOOD: Configure once in Rails
config.filter_parameters += [:password, :email, :ssn]
# E11y automatically respects this
```

**2. Add pattern-based filtering for content scanning**
```ruby
# ✅ GOOD: Catch PII in content, not just keys
filter_pattern /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i,
               replacement: '[EMAIL]'
```

**3. Whitelist IDs (not PII)**
```ruby
# ✅ GOOD: IDs are OK to log
allow_parameters :user_id, :order_id, :transaction_id
```

**4. Test PII filtering**
```ruby
# ✅ GOOD: Verify filtering works
it 'filters PII' do
  Events::SomeEvent.track(email: 'test@example.com')
  expect(event[:payload][:email]).to eq('[FILTERED]')
end
```

---

### ❌ DON'T

**1. Don't duplicate configuration**
```ruby
# ❌ BAD: Duplication
config.filter_parameters += [:email]  # Rails
config.pii_filter do
  filter_parameters :email  # E11y ← Unnecessary!
end

# ✅ GOOD: Configure once
config.filter_parameters += [:email]  # Rails only
```

**2. Don't over-whitelist**
```ruby
# ❌ BAD: Whitelisting actual PII
allow_parameters :email, :phone, :address  # ← These ARE PII!

# ✅ GOOD: Only whitelist non-PII identifiers
allow_parameters :user_id, :order_id  # ← IDs, not PII
```

**3. Don't disable deep scanning without good reason**
```ruby
# ❌ BAD: PII in nested data will leak
config.pii_filter do
  deep_scan false  # ← PII in nested hashes won't be filtered!
end

# ✅ GOOD: Keep deep scanning enabled (default)
config.pii_filter do
  deep_scan true  # Default, catches nested PII
end
```

**4. Don't use same PII rules for all adapters**
```ruby
# ❌ BAD: Same strict rules everywhere
config.pii_filter do
  mask_fields :email, :ip_address
  # Applied to ALL adapters (audit, OTel, Sentry, etc.)
end

# ✅ GOOD: Per-adapter rules based on purpose
config.pii_filter do
  # Default (most adapters)
  mask_fields :email, :ip_address
  
  # Per-adapter overrides
  adapter_overrides do
    # Audit: keep PII (compliance requirement)
    adapter :audit_file do
      skip_filtering true
    end
    
    # OTel: pseudonymize (queryable but privacy-safe)
    adapter :otlp do
      pseudonymize_fields :email, :ip_address
    end
    
    # Sentry: strict masking (external service)
    adapter :sentry do
      mask_fields :email, :ip_address, :user_id
    end
  end
end
```

---

## 🎯 Per-Adapter PII Filtering

**Problem:** Different adapters have different compliance requirements.

### Use Case: Audit Trail vs. Observability

```ruby
# Event goes to multiple adapters
class UserPermissionChanged < E11y::AuditEvent
  adapters [:audit_file, :elasticsearch, :loki, :sentry]
  
  schema do
    required(:user_email).filled(:string)
    required(:ip_address).filled(:string)
    required(:old_role).filled(:string)
    required(:new_role).filled(:string)
  end
end

# Different PII treatment per adapter:
# - audit_file: KEEP all PII (compliance)
# - elasticsearch: PSEUDONYMIZE (queryable but safe)
# - loki: MASK (observability only)
# - sentry: MASK (external service)
```

### Configuration: Global Per-Adapter Rules

```ruby
E11y.configure do |config|
  config.pii_filter do
    # Default (most adapters): strict masking
    mask_fields :email, :ip_address, :phone, :ssn
    
    # Per-adapter overrides
    adapter_overrides do
      # === Audit Log: No Filtering ===
      adapter :audit_file do
        skip_filtering true
        
        # Reason: Legal requirement to keep original data
        # Justification: GDPR Art. 6(1)(c) - "legal obligation"
        # Mitigation: Encryption + access control
      end
      
      # === Elasticsearch: Pseudonymization ===
      adapter :elasticsearch do
        # Don't mask, but hash (one-way)
        pseudonymize_fields :email, :ip_address
        hash_algorithm :sha256
        hash_salt ENV['PII_HASH_SALT']
        
        # Result: same user always same hash (queryable!)
        # email: 'john@example.com' → 'hashed_a1b2c3d4'
        # But can't reverse the hash
      end
      
      # === OpenTelemetry: Pseudonymization ===
      adapter :otlp do
        pseudonymize_fields :email, :ip_address
        hash_algorithm :sha256
        
        # Reason: OTel Semantic Conventions need some PII
        # But we can't send raw PII to external collector
      end
      
      # === Sentry: Strict Masking ===
      adapter :sentry do
        # External service: mask EVERYTHING
        mask_fields :email, :ip_address, :phone, :ssn, :user_id
        
        # Reason: Sentry is 3rd party, minimize data sharing
      end
      
      # === Loki: Default Masking ===
      adapter :loki do
        # Use default rules (mask_fields from above)
      end
    end
  end
end
```

### Configuration: Per-Event Per-Adapter Rules

```ruby
# More granular: override at event level
class SensitiveUserAction < E11y::Event::Base
  adapters [:audit_file, :elasticsearch, :sentry]
  
  schema do
    required(:user_email).filled(:string)
    required(:action).filled(:string)
  end
  
  # Override PII rules just for THIS event
  pii_rules do
    # Audit: keep everything
    adapter :audit_file do
      skip_filtering true
    end
    
    # Elasticsearch: hash email
    adapter :elasticsearch do
      pseudonymize_fields :user_email
    end
    
    # Sentry: mask email
    adapter :sentry do
      mask_fields :user_email
    end
  end
end
```

### Implementation: How It Works

```ruby
# Internal pipeline
def write_event_to_adapter(event, adapter)
  # 1. Get PII rules for this adapter
  pii_rules = get_pii_rules_for_adapter(adapter)
  
  # 2. Clone event (don't modify original)
  filtered_event = event.deep_dup
  
  # 3. Apply adapter-specific filtering
  case pii_rules.strategy
  when :skip
    # No filtering
  when :mask
    filtered_event = pii_filter.mask(filtered_event, pii_rules.fields)
  when :pseudonymize
    filtered_event = pii_filter.pseudonymize(filtered_event, pii_rules.fields)
  end
  
  # 4. Write to adapter
  adapter.write(filtered_event)
end
```

### Result: Same Event, Different PII Treatment

```ruby
# Original event:
event = {
  user_email: 'john@example.com',
  ip_address: '192.168.1.100',
  action: 'role_changed'
}

# Written to adapters:
# audit_file:      { user_email: 'john@example.com', ip_address: '192.168.1.100', ... }
# elasticsearch:   { user_email: 'hashed_a1b2c3', ip_address: 'hashed_xyz789', ... }
# loki:            { user_email: '[FILTERED]', ip_address: '[FILTERED]', ... }
# sentry:          { user_email: '[FILTERED]', ip_address: '[FILTERED]', ... }
```

### Benefits

1. ✅ **Compliance:** Audit log has original data (legal requirement)
2. ✅ **Privacy:** External services get masked data (GDPR)
3. ✅ **Queryability:** Pseudonymized data in ES (can group by user)
4. ✅ **Security:** Layered approach (different rules for different risks)

---

## 📚 Related Use Cases

- **[UC-002: Business Event Tracking](./UC-002-business-event-tracking.md)** - Event definitions
- **[UC-012: Audit Trail](./UC-012-audit-trail.md)** - Compliance logging (skip PII filtering)
- **[UC-005: Sentry Integration](./UC-005-sentry-integration.md)** - PII in error reports (strict masking)
- **[UC-008: OpenTelemetry Integration](./UC-008-opentelemetry-integration.md)** - OTel semantic conventions (pseudonymization)

---

## 🔒 GDPR Compliance

### Key GDPR Requirements Met

1. ✅ **Data Minimization** - Only log what's needed (filter PII)
2. ✅ **Purpose Limitation** - Logs for observability only
3. ✅ **Storage Limitation** - Set retention policies in adapters
4. ✅ **Integrity & Confidentiality** - PII filtered at source
5. ✅ **Accountability** - Audit which PII was filtered (sampling)

### Configuration for GDPR

```ruby
E11y.configure do |config|
  config.pii_filter do
    # GDPR-compliant defaults
    use_rails_filter_parameters true
    
    # Filter all personal data
    filter_parameters :email, :name, :address, :phone, :ssn, 
                     :birth_date, :ip_address
    
    # Content scanning
    filter_pattern /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i,
                   replacement: '[EMAIL]'
    filter_pattern /\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/,
                   replacement: '[IP]'
    
    # Sampling for compliance verification (not PII itself)
    sample_filtered_values 0.001  # 0.1% for audit
  end
end
```

---

**Document Version:** 1.0  
**Last Updated:** January 12, 2026  
**Status:** ✅ Complete
