# UC-007: PII Filtering (Rails-Compatible)

**Status:** MVP Feature (Critical for Production)  
**Complexity:** Intermediate  
**Setup Time:** 20-30 minutes  
**Target Users:** All developers, Security teams, Compliance teams

> **Approach:** Event-level `pii_filtering do` in event classes. Use inheritance for shared rules (e.g. `BaseUserEvent`). No global `config.pii_filter`.

---

## 📋 Overview

### Problem Statement

**Current Approach (Manual per-event):**
```ruby
# Each event class needs its own PII rules — duplication across similar events
# Problems:
# - Duplication across UserRegistered, UserLogin, PaymentCreated, etc.
# - Easy to forget or be inconsistent
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

### 2. Event-Level DSL + Inheritance

**Define per-event; use inheritance for shared rules:**
```ruby
# Base class — common rules for all user events
class BaseUserEvent < E11y::Event::Base
  contains_pii true
  pii_filtering do
    masks   :password, :api_key, :token
    hashes  :email
    partials :phone
    allows  :user_id, :order_id
  end
end

# Child — inherits + adds payment-specific fields
class Events::PaymentCreated < BaseUserEvent
  pii_filtering do
    masks :card_number, :cvv
  end
end
```

---

### 3. Pattern-Based Filtering (Beyond Rails)

**:explicit_pii events** (`contains_pii true`) apply `E11y::PII::Patterns::VALUE_PATTERNS` to string values (email, SSN, credit card regexes). Field-level strategies (masks, hashes, partials) are defined in `pii_filtering do`. Per-adapter overrides use `exclude_adapters`; PIIFilter produces `payload_rewrites`, Routing merges per adapter.

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

## 🔐 Explicit PII Declaration

> **Implementation:** See [ADR-006 Section 3.0.3: Explicit PII Declaration](../ADR-006-security-compliance.md#303-explicit-pii-declaration) for detailed architecture.

**Critical Design Principle:** Event classes MUST explicitly declare whether they contain PII. This enables E11y to apply the appropriate filtering tier (see Performance Tiers below) and allows linter validation.

### Why Explicit Declaration?

**Problem:** Implicit filtering leads to:
- ❌ Performance waste (filtering events that contain no PII)
- ❌ Security gaps (missing PII that should be filtered)
- ❌ No compile-time validation (typos, missing fields)

**Solution:** Explicit opt-in declaration at event class level.

---

### Declaration Syntax: `contains_pii`

**Option 1: No PII (:no_pii — Skip Filtering)**

```ruby
class Events::HealthCheck < E11y::Event::Base
  schema do
    required(:status).filled(:string)
    required(:uptime_ms).filled(:integer)
  end
  
  # ✅ Explicit: This event contains NO PII
  contains_pii false
  
  # Result:
  # - :no_pii filtering (0ms overhead)
  # - All fields logged as-is
  # - No pattern scanning
end
```

**Option 2: Default (:rails_filters — Rails Filters Only)**

```ruby
class Events::OrderCreated < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:float)
    optional(:api_key).filled(:string)  # Rails will filter this
  end
  
  # No declaration → :rails_filters (Rails filters applied)
  # Keys like :password, :token, :api_key automatically filtered
end
```

**Option 3: Explicit PII (:explicit_pii — Deep Filtering)**

```ruby
class Events::UserRegistered < E11y::Event::Base
  schema do
    required(:email).filled(:string)
    required(:password).filled(:string)
    required(:address).filled(:hash)
    required(:user_id).filled(:string)
  end
  
  # ✅ Explicit: This event contains PII
  contains_pii true
  
  # MANDATORY: Declare strategy for EVERY schema field
  pii_filtering do
    field :email do
      strategy :hash  # Pseudonymize (searchable)
    end
    
    field :password do
      strategy :mask  # Complete masking
    end
    
    field :address do
      strategy :mask  # Mask nested data
    end
    
    field :user_id do
      strategy :allow  # ID is OK to log
    end
  end
end
```

---

### Per-Field Filtering Strategies

When `contains_pii true` is declared, you MUST specify a strategy for each field in the schema:

| Strategy | Behavior | Use Case | Example Output |
|----------|----------|----------|----------------|
| `:mask` | Replace with `[FILTERED]` | Sensitive data (passwords, SSNs) | `[FILTERED]` |
| `:hash` | SHA256 hash (one-way) | Searchable identifiers (emails) | `hashed_a1b2c3d4` |
| `:allow` | No filtering | Non-PII (IDs, amounts) | Original value |
| `:partial` | Show partial (first/last chars) | Debugging (emails) | `em***@ex***` |

**Example: Payment Event with Multiple Strategies**

```ruby
class Events::PaymentProcessed < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:float)
    required(:card_number).filled(:string)
    required(:card_holder).filled(:string)
    required(:user_email).filled(:string)
    required(:ip_address).filled(:string)
  end
  
  contains_pii true
  
  pii_filtering do
    # Non-PII: allow
    field :order_id do
      strategy :allow  # ID is safe to log
    end
    
    field :amount do
      strategy :allow  # Amount is not PII
    end
    
    # Sensitive: mask completely
    field :card_number do
      strategy :mask  # Never log credit cards
    end
    
    field :card_holder do
      strategy :mask  # Cardholder name is PII
    end
    
    # Searchable: hash
    field :user_email do
      strategy :hash  # Pseudonymize for correlation
    end
    
    # Debugging: partial
    field :ip_address do
      strategy :partial  # Show '192.168.1.x'
    end
  end
end

# Track event:
Events::PaymentProcessed.track(
  order_id: 'o123',
  amount: 99.99,
  card_number: '4111-1111-1111-1111',
  card_holder: 'John Doe',
  user_email: 'john@example.com',
  ip_address: '192.168.1.100'
)

# Logged as:
# {
#   order_id: 'o123',                      # ← Allowed (ID)
#   amount: 99.99,                         # ← Allowed (not PII)
#   card_number: '[FILTERED]',             # ← Masked
#   card_holder: '[FILTERED]',             # ← Masked
#   user_email: 'hashed_7a8b9c',           # ← Hashed
#   ip_address: '192.168.1.x'              # ← Partial
# }
```

---

### Per-Adapter Overrides

Different adapters may have different PII requirements (e.g., audit trail needs full data for compliance):

```ruby
class Events::SensitiveUserAction < E11y::Event::Base
  schema do
    required(:user_email).filled(:string)
    required(:action).filled(:string)
  end
  
  contains_pii true
  
  pii_filtering do
    field :user_email do
      # Default: hash for most adapters
      strategy :hash
      
      # Override per adapter
      exclude_adapters [:file_audit]  # Audit needs original (GDPR Art. 6(1)(c))
    end
    
    field :action do
      strategy :allow  # Action type is not PII
    end
  end
end

# Result:
# - audit_file adapter:  { user_email: 'john@example.com' }  (original)
# - elasticsearch:       { user_email: 'hashed_a1b2c3' }     (hashed)
# - loki:                { user_email: 'hashed_a1b2c3' }     (hashed)
# - sentry:              { user_email: 'hashed_a1b2c3' }     (hashed)
```

---

### Linter Validation

When `contains_pii true` is declared, E11y linter validates:

1. ✅ **Every schema field has a filtering strategy** (no missing fields)
2. ✅ **No extra fields** (typos in field names)
3. ✅ **Valid strategies** (`:mask`, `:hash`, `:allow`, `:partial` only)

**Example: Linter catches missing field**

```ruby
class Events::UserLogin < E11y::Event::Base
  schema do
    required(:email).filled(:string)
    required(:password).filled(:string)
    required(:ip_address).filled(:string)  # ← MISSING in pii_filtering!
  end
  
  contains_pii true
  
  pii_filtering do
    field :email do
      strategy :hash
    end
    
    field :password do
      strategy :mask
    end
    
    # ❌ LINTER ERROR: Field :ip_address declared in schema but missing in pii_filtering!
  end
end

# Fix:
pii_filtering do
  field :email do
    strategy :hash
  end
  
  field :password do
    strategy :mask
  end
  
  field :ip_address do  # ✅ Added
    strategy :partial
  end
end
```

---

### Default Behavior (No Declaration)

If `contains_pii` is not specified, E11y defaults to **:rails_filters** (Rails filters only):

```ruby
class Events::OrderPaid < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:float)
  end
  
  # No contains_pii declaration
  # → :rails_filters: Rails filters applied automatically
  # → Keys like :password, :token, :api_key filtered
  # → No linter validation
end
```

**Recommended for:** Standard business events where Rails filters provide sufficient coverage (90% of use cases).

---

### Migration Guide

**If you have existing events without explicit declaration:**

**Step 1: Audit events**
```bash
# List events without PII declaration
bundle exec rake e11y:audit:pii_declarations

# Output:
# ⚠️  Events without PII declaration (using Tier 2 default):
# - Events::OrderCreated
# - Events::PaymentProcessed
# - Events::UserLogin
# 
# ✅ Events with PII declaration:
# - Events::HealthCheck (contains_pii false)
# - Events::UserRegistered (contains_pii true)
```

**Step 2: Add declarations**
```ruby
# For events with NO user data:
class Events::HealthCheck < E11y::Event::Base
  contains_pii false  # ✅ Explicit
end

# For events with PII:
class Events::UserLogin < E11y::Event::Base
  contains_pii true  # ✅ Explicit
  
  pii_filtering do
    # ... declare strategies for ALL fields
  end
end

# For standard events (keep default):
class Events::OrderCreated < E11y::Event::Base
  # No declaration (Tier 2 default is fine)
end
```

**Step 3: Enable linter in CI**
```ruby
# config/environments/test.rb
config.after_initialize do
  E11y::Linters::PiiDeclarationLinter.validate_all!
end
```

---

### Event Inheritance for PII (NEW - v1.1)

> **🎯 CONTRADICTION_01 Resolution:** Use inheritance to share common PII rules across related events.

**Base class with common PII rules:**

```ruby
# app/events/base_user_event.rb
module Events
  class BaseUserEvent < E11y::Event::Base
    # Common for ALL user events
    contains_pii true
    
    pii_filtering do
      # Common PII handling
      hashes :email, :phone  # Pseudonymize for searchability
      allows :user_id        # ID is not PII
    end
  end
end

# Inherit and extend
class Events::UserRegistered < Events::BaseUserEvent
  schema do
    required(:user_id).filled(:string)
    required(:email).filled(:string)
    required(:password).filled(:string)
    required(:phone).filled(:string)
  end
  
  pii_filtering do
    # Inherits: hashes :email, :phone + allows :user_id
    # Add more:
    masks :password  # ← Additional field
  end
end

class Events::UserProfileUpdated < Events::BaseUserEvent
  schema do
    required(:user_id).filled(:string)
    required(:email).filled(:string)
    required(:phone).filled(:string)
    required(:address).filled(:hash)
  end
  
  pii_filtering do
    # Inherits: hashes :email, :phone + allows :user_id
    # Add more:
    masks :address  # ← Additional field
  end
end
```

**Base class for payment events with PII:**

```ruby
# app/events/base_payment_event.rb
module Events
  class BasePaymentEvent < E11y::Event::Base
    contains_pii true
    
    pii_filtering do
      # Common payment PII handling
      hashes :email, :user_id  # Pseudonymize
      allows :order_id, :amount, :currency  # Non-PII
      masks :card_number, :cvv  # Sensitive
    end
  end
end

# Inherit from base
class Events::PaymentSucceeded < Events::BasePaymentEvent
  schema do
    required(:transaction_id).filled(:string)
    required(:order_id).filled(:string)
    required(:user_id).filled(:string)
    required(:email).filled(:string)
    required(:amount).filled(:decimal)
    required(:currency).filled(:string)
    required(:card_number).filled(:string)
  end
  # ← Inherits ALL PII rules from BasePaymentEvent!
end

class Events::PaymentFailed < Events::BasePaymentEvent
  schema do
    required(:transaction_id).filled(:string)
    required(:order_id).filled(:string)
    required(:user_id).filled(:string)
    required(:email).filled(:string)
    required(:amount).filled(:decimal)
    required(:error_code).filled(:string)
  end
  # ← Inherits ALL PII rules from BasePaymentEvent!
end
```

**Benefits:**
- ✅ DRY (common PII rules shared)
- ✅ Consistency (all user events handle PII same way)
- ✅ Easy to update (change base → all events updated)
- ✅ Linter validates base + child (complete coverage)

**Preset modules for PII:**

```ruby
# lib/e11y/presets/pii_aware_event.rb
module E11y
  module Presets
    module PiiAwareEvent
      extend ActiveSupport::Concern
      included do
        contains_pii true
        
        pii_filtering do
          # Common PII patterns
          hashes :email, :phone, :ip_address
          masks :password, :token, :api_key, :secret
          allows :user_id, :order_id, :transaction_id
        end
      end
    end
  end
end

# Usage:
class Events::UserAction < E11y::Event::Base
  include E11y::Presets::PiiAwareEvent  # ← Common PII rules!
  
  schema do
    required(:user_id).filled(:string)
    required(:email).filled(:string)
    required(:action).filled(:string)
  end
  
  pii_filtering do
    # Inherits: hashes :email + allows :user_id
    # Add more if needed:
    allows :action  # ← Additional field
  end
end
```

---

## ⚡ DSL Shortcuts (Rails-Style)

> **Implementation:** See [ADR-006 Section 3.4.4: Configuration API (Rails-Style DSL)](../ADR-006-security-compliance.md#344-configuration-api-rails-style-dsl) for detailed architecture.

E11y provides **Rails-style DSL shortcuts** to simplify PII declarations. Instead of verbose `field` blocks, use one-liner shortcuts like `masks`, `hashes`, `skips` – similar to Rails validations.

### Why DSL Shortcuts?

**Problem:** Verbose declarations for simple cases:

```ruby
# ❌ Verbose: 15 lines for 3 fields
pii_filtering do
  field :password do
    strategy :mask
  end
  
  field :token do
    strategy :mask
  end
  
  field :secret_key do
    strategy :mask
  end
end
```

**Solution:** Rails-style shortcuts (like `validates :name, presence: true`):

```ruby
# ✅ Concise: 3 lines for 3 fields
pii_filtering do
  masks :password, :token, :secret_key
end
```

---

### Basic Shortcuts

**`masks(*fields)`** - Complete masking (replace with `[FILTERED]`)

```ruby
class Events::UserLogin < E11y::Event::Base
  schema do
    required(:password).filled(:string)
    required(:token).filled(:string)
    required(:api_key).filled(:string)
  end
  
  contains_pii true
  
  pii_filtering do
    # Mask multiple fields at once
    masks :password, :token, :api_key
  end
end

# Equivalent to:
# field :password do; strategy :mask; end
# field :token do; strategy :mask; end
# field :api_key do; strategy :mask; end
```

**`hashes(*fields)`** - Pseudonymization (SHA256 hash)

```ruby
class Events::UserRegistered < E11y::Event::Base
  schema do
    required(:email).filled(:string)
    required(:phone).filled(:string)
    required(:ip_address).filled(:string)
  end
  
  contains_pii true
  
  pii_filtering do
    # Hash for searchability
    hashes :email, :phone, :ip_address
  end
end

# Result:
# {
#   email: 'hashed_a1b2c3d4...',  # SHA256 of 'user@example.com'
#   phone: 'hashed_xyz789...',    # SHA256 of '+1-555-1234'
#   ip_address: 'hashed_abc...'   # SHA256 of '192.168.1.100'
# }
```

**`allows(*fields)`** - No filtering (explicitly safe)

```ruby
class Events::OrderPaid < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:float)
    required(:currency).filled(:string)
  end
  
  contains_pii true  # Event has PII elsewhere
  
  pii_filtering do
    # Explicitly mark as non-PII
    allows :order_id, :amount, :currency
  end
end
```

**`partials(*fields)`** - Partial masking (show first/last chars)

```ruby
class Events::SupportTicket < E11y::Event::Base
  schema do
    required(:email).filled(:string)
    required(:phone).filled(:string)
  end
  
  contains_pii true
  
  pii_filtering do
    # Show partial for debugging
    partials :email, :phone
  end
end

# Result:
# {
#   email: 'em***@ex***',      # user@example.com → em***@ex***
#   phone: '+1-***-***-4567'   # +1-555-123-4567 → +1-***-***-4567
# }
```

---

### Combined Example: Payment Processing

```ruby
class Events::PaymentProcessed < E11y::Event::Base
  schema do
    # PII fields
    required(:card_number).filled(:string)
    required(:card_holder).filled(:string)
    required(:user_email).filled(:string)
    required(:billing_address).filled(:hash)
    
    # Non-PII fields
    required(:order_id).filled(:string)
    required(:amount).filled(:float)
    required(:currency).filled(:string)
  end
  
  contains_pii true
  
  pii_filtering do
    # Sensitive: complete masking
    masks :card_number, :card_holder, :billing_address
    
    # Searchable: hashing
    hashes :user_email
    
    # Non-PII: explicitly allowed
    allows :order_id, :amount, :currency
  end
end

# Compare to verbose version (15+ lines):
# pii_filtering do
#   field :card_number do; strategy :mask; end
#   field :card_holder do; strategy :mask; end
#   field :billing_address do; strategy :mask; end
#   field :user_email do; strategy :hash; end
#   field :order_id do; strategy :allow; end
#   field :amount do; strategy :allow; end
#   field :currency do; strategy :allow; end
# end
```

---

### Advanced Shortcuts

**Per-Adapter Exclusions**

```ruby
class Events::SensitiveAction < E11y::Event::Base
  schema do
    required(:user_email).filled(:string)
    required(:action).filled(:string)
  end
  
  contains_pii true
  
  pii_filtering do
    # Hash email, but keep original in audit
    hashes :user_email, exclude_adapters: [:file_audit]
    
    # Action is not PII
    allows :action
  end
end

# Result:
# audit_file:     { user_email: 'john@example.com' }  (original)
# elasticsearch:  { user_email: 'hashed_a1b2c3' }     (hashed)
# loki:           { user_email: 'hashed_a1b2c3' }     (hashed)
```

**Conditional Filtering (Rails-style)**

```ruby
class Events::UserAction < E11y::Event::Base
  schema do
    required(:email).filled(:string)
    required(:admin_flag).filled(:bool)
  end
  
  contains_pii true
  
  pii_filtering do
    # Only mask in production
    masks_if -> { Rails.env.production? }, :email
    
    # Admin flag is not PII
    allows :admin_flag
  end
end
```

**Grouping with `with_strategy`**

```ruby
class Events::UserProfile < E11y::Event::Base
  schema do
    required(:password).filled(:string)
    required(:token).filled(:string)
    required(:secret_key).filled(:string)
    required(:email).filled(:string)
    required(:phone).filled(:string)
  end
  
  contains_pii true
  
  pii_filtering do
    # Group fields by strategy
    with_strategy :mask do
      field :password
      field :token
      field :secret_key
    end
    
    with_strategy :hash do
      field :email
      field :phone
    end
  end
end

# Equivalent to:
# masks :password, :token, :secret_key
# hashes :email, :phone
```

**Bulk Operations**

```ruby
class Events::ComplexEvent < E11y::Event::Base
  schema do
    required(:password).filled(:string)
    required(:token).filled(:string)
    required(:email).filled(:string)
    required(:phone).filled(:string)
    required(:order_id).filled(:string)
    required(:amount).filled(:float)
  end
  
  contains_pii true
  
  pii_filtering do
    # Mask everything EXCEPT safe fields
    masks_all_except :order_id, :amount
  end
end

# Result: password, token, email, phone → masked
#         order_id, amount → allowed
```

---

### Cheat Sheet: Shortcuts vs. Strategies

| Shortcut | Strategy | Output Example | Use Case |
|----------|----------|----------------|----------|
| `masks` | `:mask` | `[FILTERED]` | Passwords, secrets, credit cards |
| `hashes` | `:hash` | `hashed_a1b2c3` | Emails, phones (searchable) |
| `allows` | `:allow` | Original value | IDs, amounts (non-PII) |
| `partials` | `:partial` | `em***@ex***` | Debugging (show partial) |

---

### When to Use Shortcuts vs. Verbose DSL

**Use Shortcuts:**
```ruby
# ✅ GOOD: Simple cases with same strategy
pii_filtering do
  masks :password, :token, :api_key
  hashes :email, :phone
  allows :order_id, :amount
end
```

**Use Verbose DSL:**
```ruby
# ✅ GOOD: Complex per-field configuration
pii_filtering do
  field :email do
    strategy :hash
    hash_algorithm :sha256
    hash_salt ENV['PII_SALT']
    exclude_adapters [:file_audit]
  end
  
  field :ip_address do
    strategy :partial
    custom_for_adapter :loki do
      ->(value) { value.split('.')[0..2].join('.') + '.x' }
    end
  end
end
```

---

### Migration: Verbose → Shortcuts

**Before (Verbose):**
```ruby
class Events::UserLogin < E11y::Event::Base
  contains_pii true
  
  pii_filtering do
    field :password do
      strategy :mask
    end
    
    field :email do
      strategy :hash
    end
    
    field :user_id do
      strategy :allow
    end
  end
end
```

**After (Shortcuts):**
```ruby
class Events::UserLogin < E11y::Event::Base
  contains_pii true
  
  pii_filtering do
    masks :password
    hashes :email
    allows :user_id
  end
end

# Or even shorter:
# pii_filtering do
#   masks :password
#   hashes :email
#   allows :user_id
# end
```

---

### Best Practices

**1. Use shortcuts for simple cases**
```ruby
# ✅ GOOD: Clear and concise
masks :password, :token
hashes :email, :phone
```

**2. Group related fields**
```ruby
# ✅ GOOD: Grouped by purpose
pii_filtering do
  # Credentials: mask completely
  masks :password, :token, :api_key
  
  # Identifiers: hash for searchability
  hashes :email, :phone, :user_id
  
  # Business data: allow
  allows :order_id, :amount, :currency
end
```

**3. Use verbose DSL for complex config**
```ruby
# ✅ GOOD: Complex per-adapter rules need verbose syntax
field :email do
  strategy :hash
  exclude_adapters [:file_audit]
  custom_for_adapter :loki do
    ->(value) { mask_domain(value) }
  end
end
```

**4. Don't mix shortcuts and verbose for same strategy**
```ruby
# ❌ BAD: Mixing shortcuts and verbose
masks :password
field :token do; strategy :mask; end  # ← Should use shortcut

# ✅ GOOD: Consistent style
masks :password, :token
```

---

## 🔍 Linter Enforcement

> **Implementation:** See [ADR-006 Section 3.0.5: PII Declaration Linter](../ADR-006-security-compliance.md#305-pii-declaration-linter) for detailed architecture.

E11y includes a **PII Declaration Linter** that validates PII handling at boot time and in CI. This catches missing declarations, typos, and incomplete coverage BEFORE code reaches production.

### Why Linter Enforcement?

**Problem:** Manual PII declaration is error-prone:
- ❌ Forget to declare a field → PII leaks to logs
- ❌ Typo in field name → Declaration doesn't apply
- ❌ Add new field, forget PII strategy → Security gap

**Solution:** Linter validates at boot time (development/test) and in CI.

---

### What the Linter Checks

When `contains_pii true` is declared, the linter enforces:

1. ✅ **Every schema field has a filtering strategy** (completeness)
2. ✅ **No extra fields in pii_filtering** (no typos)
3. ✅ **Valid strategies only** (`:mask`, `:hash`, `:allow`, `:partial`)
4. ✅ **Adapter exclusions are valid** (adapter exists)

**Example: Linter Catches Missing Field**

```ruby
class Events::UserLogin < E11y::Event::Base
  schema do
    required(:email).filled(:string)
    required(:password).filled(:string)
    required(:ip_address).filled(:string)  # ← Missing in pii_filtering!
  end
  
  contains_pii true
  
  pii_filtering do
    field :email do
      strategy :hash
    end
    
    field :password do
      strategy :mask
    end
    
    # ❌ Missing: :ip_address
  end
end

# Boot output:
# ❌ E11y::Linters::PiiDeclarationError:
#    Missing PII declaration for Events::UserLogin
#    
#    Schema fields:   [:email, :password, :ip_address]
#    Declared fields: [:email, :password]
#    Missing:         [:ip_address]
#    
#    Fix: Add pii_filtering for :ip_address
```

**Example: Linter Catches Typo**

```ruby
class Events::PaymentProcessed < E11y::Event::Base
  schema do
    required(:card_number).filled(:string)
    required(:amount).filled(:float)
  end
  
  contains_pii true
  
  pii_filtering do
    field :card_numbre do  # ← Typo: numbre instead of number
      strategy :mask
    end
    
    field :amount do
      strategy :allow
    end
  end
end

# Boot output:
# ❌ E11y::Linters::PiiDeclarationError:
#    Invalid PII declarations for Events::PaymentProcessed
#    
#    Schema fields:   [:card_number, :amount]
#    Declared fields: [:card_numbre, :amount]
#    Extra:           [:card_numbre]  # ← Not in schema (typo?)
#    Missing:         [:card_number]  # ← Not declared
#    
#    Fix: Check field names match schema exactly
```

---

### Running the Linter

**Option 1: Boot-Time Validation (Development/Test)**

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  # ... other config ...
  
  # Validate PII declarations at boot
  if Rails.env.development? || Rails.env.test?
    config.after_initialize do
      E11y::Linters::PiiDeclarationLinter.validate_all!
    end
  end
end

# Result: App won't boot if PII declarations invalid
# $ rails server
# => Booting Puma
# => Rails 7.1.2 application starting in development
# => Run `bin/rails server --help` for more startup options
# ❌ E11y::Linters::PiiDeclarationError: Missing PII declaration for Events::UserLogin
# ... (detailed error message) ...
```

**Option 2: Rake Task (CI/Manual)**

```bash
# Run PII linter manually
bundle exec rake e11y:lint:pii

# Output:
# Checking PII declarations...
# ================================================================================
# ✅ Events::UserRegistered - All 4 fields declared
# ✅ Events::PaymentProcessed - All 6 fields declared
# ⚪ Events::HealthCheck - No PII (skipped)
# ⚪ Events::OrderCreated - No PII declaration (Tier 2 default)
# ❌ Events::UserLogin - Missing declarations
# ================================================================================
# 
# ❌ ERRORS:
# 
# Missing PII declaration for Events::UserLogin
# Schema fields:   [:email, :password, :ip_address]
# Declared fields: [:email, :password]
# Missing:         [:ip_address]
# 
# Fix: Add pii_filtering for :ip_address
# 
# Exit code: 1 (fails CI build)
```

**Option 3: RSpec Matcher (Unit Tests)**

```ruby
# spec/support/e11y_pii_matchers.rb
RSpec::Matchers.define :have_complete_pii_declaration do
  match do |event_class|
    return true unless event_class.contains_pii?
    
    E11y::Linters::PiiDeclarationLinter.validate!(event_class)
    true
  rescue E11y::Linters::PiiDeclarationError => e
    @error_message = e.message
    false
  end
  
  failure_message do |event_class|
    "Expected #{event_class.name} to have complete PII declaration, but:\n#{@error_message}"
  end
end

# spec/events/user_login_spec.rb
RSpec.describe Events::UserLogin do
  it { is_expected.to have_complete_pii_declaration }
end

# Test output if declaration incomplete:
# ❌ Expected Events::UserLogin to have complete PII declaration, but:
#    Missing PII declaration for Events::UserLogin
#    Schema fields:   [:email, :password, :ip_address]
#    Declared fields: [:email, :password]
#    Missing:         [:ip_address]
```

---

### Linter Configuration

**Enable/Disable Linter**

```ruby
E11y.configure do |config|
  config.pii_linter do
    # Enable in development/test (default: true)
    enabled Rails.env.development? || Rails.env.test?
    
    # Fail on errors (default: true)
    fail_on_error true
    
    # Log warnings for default (Tier 2) events (default: false)
    warn_on_default_tier false
  end
end
```

**Custom Linter Rules**

```ruby
E11y.configure do |config|
  config.pii_linter do
    # Enforce explicit declaration for ALL events (even Tier 2)
    require_explicit_declaration true  # Default: false
    
    # Allowed strategies (customize if needed)
    allowed_strategies [:mask, :hash, :allow, :partial]
    
    # Forbidden strategies (never allow)
    forbidden_strategies [:skip]  # Force explicit :allow instead
  end
end
```

---

### CI Integration

**GitHub Actions Example**

```yaml
# .github/workflows/ci.yml
name: CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v3
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.2
          bundler-cache: true
      
      # Run PII linter BEFORE tests
      - name: Validate PII Declarations
        run: bundle exec rake e11y:lint:pii
      
      # Run tests only if linter passes
      - name: Run tests
        run: bundle exec rspec
```

**GitLab CI Example**

```yaml
# .gitlab-ci.yml
test:
  stage: test
  script:
    # Fail fast if PII declarations invalid
    - bundle exec rake e11y:lint:pii
    - bundle exec rspec
```

---

### Audit Report

Generate a report of all PII declarations:

```bash
# Generate PII audit report
bundle exec rake e11y:audit:pii_declarations

# Output:
# E11y PII Declaration Audit Report
# ================================================================================
# Generated: 2026-01-14 10:30:00 UTC
# Total Events: 42
# 
# 📊 SUMMARY:
# - contains_pii true:  8 events (19%)
# - contains_pii false: 5 events (12%)
# - No declaration:    29 events (69%, using Tier 2 default)
# 
# 📋 TIER 3 EVENTS (contains_pii true):
# 
# ✅ Events::UserRegistered
#    Fields: [:email, :password, :address, :user_id]
#    Strategies: hash(1), mask(2), allow(1)
#    Adapters excluded: [:file_audit] for [:email, :address]
# 
# ✅ Events::PaymentProcessed
#    Fields: [:card_number, :amount, :user_email]
#    Strategies: mask(1), allow(1), hash(1)
#    Adapters excluded: none
# 
# ... (more events) ...
# 
# 📋 TIER 1 EVENTS (contains_pii false):
# 
# ⚪ Events::HealthCheck
#    Fields: [:status, :uptime_ms]
#    PII filtering: SKIPPED (performance optimized)
# 
# ... (more events) ...
# 
# ⚠️  TIER 2 EVENTS (no declaration, default filtering):
# 
# 🔵 Events::OrderCreated
#    Fields: [:order_id, :amount, :api_key]
#    PII filtering: Rails filters only (Tier 2 default)
#    Recommendation: Keep default (sufficient for standard events)
# 
# ... (more events) ...
# 
# ================================================================================
# 
# 💡 RECOMMENDATIONS:
# - 29 events use Tier 2 default (Rails filters)
# - Consider adding contains_pii false to high-frequency events (health checks)
# - All Tier 3 events have complete declarations ✅
```

---

### Best Practices

**1. Enable linter in development/test**
```ruby
# ✅ GOOD: Catch errors early
config.after_initialize do
  E11y::Linters::PiiDeclarationLinter.validate_all!
end
```

**2. Run linter in CI before tests**
```bash
# ✅ GOOD: Fail fast
bundle exec rake e11y:lint:pii && bundle exec rspec
```

**3. Use RSpec matchers for new events**
```ruby
# ✅ GOOD: Test-driven PII declarations
RSpec.describe Events::NewEvent do
  it { is_expected.to have_complete_pii_declaration }
end
```

**4. Review audit report periodically**
```bash
# ✅ GOOD: Ensure no PII leaks over time
bundle exec rake e11y:audit:pii_declarations > pii_audit_$(date +%Y%m%d).txt
```

**5. Don't disable linter in production**
```ruby
# ❌ BAD: Linter should not run in production (performance)
# Boot-time validation is for dev/test only

# ✅ GOOD: Enable only in non-production
if Rails.env.development? || Rails.env.test?
  E11y::Linters::PiiDeclarationLinter.validate_all!
end
```

---

## ⚡ Performance Tiers

> **Implementation:** See [ADR-006 Section 3.0: PII Filtering Strategy](../ADR-006-security-compliance.md#30-pii-filtering-strategy) for detailed architecture.

E11y uses a **3-tier filtering strategy** to balance security and performance. Filtering ALL events by default would create massive overhead (1M events × 0.2ms = 200 seconds CPU/day). Instead, events are categorized into 3 tiers based on PII content.

### Overview: 3-Tier Strategy

| Tier | Strategy | Overhead | Use Case | Events/sec |
|------|----------|----------|----------|------------|
| **Tier 1** | Skip filtering | 0ms | Health checks, metrics, internal events | 500 |
| **Tier 2** | Rails filters only | ~0.05ms | Standard events (known PII keys) | 400 |
| **Tier 3** | Deep filtering | ~0.2ms | User data, payments, complex nested | 100 |

**Performance Budget:**
```
500 events/sec × 0ms     = 0ms CPU/sec      (Tier 1)
400 events/sec × 0.05ms  = 20ms CPU/sec     (Tier 2)
100 events/sec × 0.2ms   = 20ms CPU/sec     (Tier 3)
----
Total: 40ms CPU/sec = 4% CPU on single core ✅
```

---

### Tier 1: No PII (Skip Filtering)

**Use when:** Event contains NO personal data (health checks, metrics, system events).

**How to declare:**
```ruby
class Events::HealthCheck < E11y::Event::Base
  schema do
    required(:status).filled(:string)
    required(:uptime_ms).filled(:integer)
  end
  
  # ✅ Explicit: This event contains NO PII
  contains_pii false  # Skip all PII filtering
end

# Result: 0ms overhead per event
```

**Performance:**
```ruby
# Benchmark: 1000 events
Benchmark.ips do |x|
  x.report('Tier 1 - No PII') do
    Events::HealthCheck.track(status: 'ok', uptime_ms: 12345)
  end
end

# Results:
# Tier 1 - No PII: 10,000 i/s (100μs per event)
# Overhead: 0ms (no filtering)
```

**When to use:**
- ✅ Health checks
- ✅ Performance metrics
- ✅ System heartbeats
- ✅ Resource usage events
- ❌ Anything with user data

---

### Tier 2: Rails Filters Only (Default)

**Use when:** Event has simple PII (passwords, tokens, API keys) already in `Rails.filter_parameters`.

**How to declare:**
```ruby
class Events::OrderCreated < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:float)
    optional(:api_key).filled(:string)
  end
  
  # No declaration → Rails filters applied automatically (Tier 2)
  # Filters keys like: password, token, secret, api_key
end

# Result: ~0.05ms overhead per event
```

**How it works:**
```ruby
# Rails config (single source of truth)
Rails.application.config.filter_parameters += [:password, :email, :token]

# E11y automatically applies these filters
Events::OrderCreated.track(
  order_id: 'o123',
  amount: 99.99,
  api_key: 'sk_live_xxx'  # ← Filtered by Rails config
)

# Logged as:
# {
#   order_id: 'o123',
#   amount: 99.99,
#   api_key: '[FILTERED]'  # ← Rails filter applied
# }
```

**Performance:**
```ruby
# Benchmark: 1000 events
Benchmark.ips do |x|
  x.report('Tier 2 - Rails filters') do
    Events::OrderCreated.track(order_id: 'o123', api_key: 'secret')
  end
end

# Results:
# Tier 2 - Rails filters: 8,000 i/s (125μs per event)
# Overhead: ~0.05ms (simple key matching)
```

**When to use:**
- ✅ Standard business events (orders, payments)
- ✅ Simple PII (known keys: password, token, email)
- ✅ Most application events (90% of use cases)
- ❌ Complex nested data with PII in content

---

### Tier 3: Deep Filtering (Explicit PII)

**Use when:** Event contains complex PII (nested data, emails in content, credit cards).

**How to declare:**
```ruby
class Events::UserRegistered < E11y::Event::Base
  schema do
    required(:email).filled(:string)
    required(:password).filled(:string)
    required(:address).filled(:hash)
    required(:user_id).filled(:string)
  end
  
  # ✅ Explicit: This event contains PII
  contains_pii true  # Tier 3: Deep filtering + content scanning
  
  pii_filtering do
    field :email do
      strategy :hash  # Pseudonymize for searchability
    end
    
    field :password do
      strategy :mask  # Complete masking
    end
    
    field :address do
      strategy :mask  # Mask nested hash
    end
    
    field :user_id do
      strategy :allow  # ID is OK to log
    end
  end
end

# Result: ~0.2ms overhead per event
```

**What Deep Filtering does:**
1. **Key-based filtering:** Filters fields by name (like Tier 2)
2. **Pattern scanning:** Scans string content for emails, credit cards, SSNs
3. **Nested traversal:** Recursively filters hashes and arrays
4. **Custom filters:** Applies per-field strategies (mask/hash/allow)

**Performance:**
```ruby
# Benchmark: 1000 events with nested data
Benchmark.ips do |x|
  x.report('Tier 3 - Deep filtering') do
    Events::UserRegistered.track(
      email: 'user@example.com',
      password: 'secret123',
      address: { street: '123 Main', city: 'NYC' }
    )
  end
end

# Results:
# Tier 3 - Deep filtering: 5,000 i/s (200μs per event)
# Overhead: ~0.2ms (deep traversal + pattern matching)
```

**When to use:**
- ✅ User registration/profile updates
- ✅ Payment processing (credit cards)
- ✅ Support tickets (PII in content)
- ✅ Complex nested data structures
- ⚠️ Use sparingly (higher overhead)

---

### Choosing the Right Tier

**Decision Tree:**

```
Does event contain ANY user data?
├─ NO → Tier 1 (contains_pii false)
│   └─ Examples: health checks, metrics, system events
│
└─ YES → Does data have nested structures or PII in content?
    ├─ NO → Tier 2 (default, no declaration)
    │   └─ Examples: orders, standard business events
    │
    └─ YES → Tier 3 (contains_pii true)
        └─ Examples: user profiles, payments, support tickets
```

**Performance Comparison:**

```ruby
# Tracking 1000 events of each tier:

# Tier 1: 100ms (no filtering)
1000.times { Events::HealthCheck.track(status: 'ok') }

# Tier 2: 150ms (+50ms overhead from Rails filters)
1000.times { Events::OrderCreated.track(order_id: 'o1', api_key: 'secret') }

# Tier 3: 300ms (+200ms overhead from deep filtering)
1000.times { Events::UserRegistered.track(email: 'u@x.com', address: {...}) }
```

**Best Practices:**

1. ✅ **Default to Tier 2:** Most events don't need deep filtering
2. ✅ **Use Tier 1 for high-frequency events:** Health checks, metrics (avoid overhead)
3. ✅ **Reserve Tier 3 for true PII events:** User data, payments, support tickets
4. ⚠️ **Monitor performance impact:** Use self-monitoring metrics (see below)

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

## 🔒 Validations (NEW - v1.1)

> **🎯 Pattern:** Validate PII configuration at class load time.

### PII Strategy Validation

**Problem:** Invalid PII strategies → runtime errors.

**Solution:** Validate strategy against whitelist:

```ruby
# Gem implementation (automatic):
VALID_PII_STRATEGIES = [:mask, :hash, :remove, :allow]

def self.pii_filtering(&block)
  # Validate strategies during DSL execution
  # Raises ArgumentError if invalid strategy used
end

# Result:
class Events::UserRegistered < E11y::Event::Base
  contains_pii true
  pii_filtering do
    encrypts :email  # ← ERROR: "Invalid PII strategy: :encrypts. Valid: mask, hash, remove, allow"
  end
end
```

### PII Field Existence Validation

**Problem:** Typos in PII field names → fields not filtered.

**Solution:** Validate against schema fields:

```ruby
# Gem implementation (automatic):
def self.pii_filtering(&block)
  # After schema is defined, validate PII fields exist
  pii_fields = extract_pii_fields_from_block(block)
  schema_fields = self.schema.keys
  
  invalid_fields = pii_fields - schema_fields
  if invalid_fields.any?
    raise ArgumentError, "PII fields not in schema: #{invalid_fields.join(', ')}"
  end
end

# Result:
class Events::UserRegistered < E11y::Event::Base
  schema do
    required(:email).filled(:string)
    required(:name).filled(:string)
  end
  
  contains_pii true
  pii_filtering do
    masks :email, :username  # ← ERROR: "PII fields not in schema: username"
  end
end
```

---

## 🌍 Environment-Specific PII Configuration (NEW - v1.1)

> **🎯 Pattern:** Different PII strategies per environment.

### Example 1: Strict Masking in Production

```ruby
class Events::UserRegistered < E11y::Event::Base
  schema do
    required(:email).filled(:string)
    required(:name).filled(:string)
    required(:ip_address).filled(:string)
  end
  
  contains_pii true
  pii_filtering do
    if Rails.env.production?
      # Production: strict masking
      masks :email, :name, :ip_address
    else
      # Dev/Test: allow for debugging
      allows :email, :name, :ip_address
    end
  end
end
```

### Example 2: Jurisdiction-Specific Hashing

```ruby
class Events::PaymentProcessed < E11y::Event::Base
  schema do
    required(:user_id).filled(:string)
    required(:credit_card_last4).filled(:string)
  end
  
  contains_pii true
  pii_filtering do
    case ENV['JURISDICTION']
    when 'EU'
      # GDPR: pseudonymization (reversible)
      hashes :user_id, algorithm: :sha256, salt: ENV['PII_SALT']
      masks :credit_card_last4
    when 'US'
      # US: allow user_id (not PII), mask card
      allows :user_id
      masks :credit_card_last4
    else
      # Default: strict masking
      masks :user_id, :credit_card_last4
    end
  end
end
```

---

## 📊 Precedence Rules for PII (NEW - v1.1)

> **🎯 Pattern:** PII configuration precedence (most specific wins).

### Precedence Order (Highest to Lowest)

```
1. Event-level pii_filtering block (highest)
   ↓
2. Preset module PII config
   ↓
3. Base class PII config
   ↓
4. Rails.application.config.filter_parameters
   ↓
5. Global E11y.config.pii_filter (lowest)
```

### Example: Mixing Inheritance + Presets for PII

```ruby
# Global config (lowest priority)
E11y.configure do |config|
  config.pii_filter do
    use_rails_filter_parameters true  # Use Rails config
    masks :password, :ssn  # Additional global masks
  end
end

# Rails config (used by global)
Rails.application.config.filter_parameters += [:email, :phone]

# Base class (medium priority)
class Events::BaseUserEvent < E11y::Event::Base
  contains_pii true
  pii_filtering do
    hashes :user_id, :email  # Override global (hash instead of mask)
    allows :name  # Allow name (not PII in this context)
  end
end

# Preset module (higher priority)
module E11y::Presets::PiiAwareEvent
  extend ActiveSupport::Concern
  included do
    contains_pii true
    pii_filtering do
      masks :ip_address, :session_id  # Additional masks
    end
  end
end

# Event (highest priority)
class Events::UserLogin < Events::BaseUserEvent
  include E11y::Presets::PiiAwareEvent
  
  pii_filtering do
    allows :email  # Override base (allow email for login events)
  end
  
  # Final PII config:
  # - user_id: hashed (from base)
  # - email: allowed (event-level override)
  # - name: allowed (from base)
  # - ip_address: masked (from preset)
  # - session_id: masked (from preset)
  # - password: masked (from global)
  # - ssn: masked (from global)
  # - phone: masked (from Rails config)
end
```

### PII Precedence Rules Table

| Field | Global | Rails Config | Base Class | Preset | Event-Level | Winner |
|-------|--------|--------------|------------|--------|-------------|--------|
| `email` | `mask` | `mask` | `hash` | - | `allow` | **`allow`** (event) |
| `user_id` | - | - | `hash` | - | - | **`hash`** (base) |
| `ip_address` | - | - | - | `mask` | - | **`mask`** (preset) |
| `password` | `mask` | - | - | - | - | **`mask`** (global) |
| `phone` | - | `mask` | - | - | - | **`mask`** (Rails) |

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

**Document Version:** 1.1 (Unified DSL)  
**Last Updated:** January 16, 2026  
**Status:** ✅ Complete - Consistent with DSL-SPECIFICATION.md v1.1.0
