# E11y Event Routing: Complete Flow Diagrams

**Date:** 2026-01-27  
**Purpose:** Visual explanation of event routing for ALL event types

---

## 📊 Overview

ALL events in E11y go through routing. Three types of events:
1. **Regular events** - Normal application events (info, warn, error)
2. **Audit events** - Compliance-critical events (UC-012)
3. **High-priority events** - Errors, critical alerts

Routing happens in 3 ways:
1. **Explicit adapters** - Set in event class DSL
2. **Routing rules** - Dynamic routing via lambdas
3. **Fallback** - Default adapters (OK for regular, BLOCKED for audit)

---

## Flow 1: Regular Event with Severity-Based Routing

Most common case - regular application event uses severity mapping.

```mermaid
flowchart TD
    A[User calls Event.track] --> B[Event::Base#adapters method]
    B --> C{Has explicit adapters?}
    C -->|YES| D[Return explicit adapters]
    C -->|NO| E{Is audit_event?}
    E -->|NO| F[Call resolved_adapters]
    F --> G[Get severity: info, warn, error, etc]
    G --> H[adapters_for_severity mapping]
    H --> I[Return adapters by severity]
    
    I --> J[severity :info → logs]
    I --> K[severity :error → logs + errors_tracker]
    
    J --> L[Enter Pipeline]
    K --> L
    D --> L
    
    L --> M[TraceContext → Validation → PIIFilter]
    M --> N[Sampling → Routing Middleware]
    
    N --> O{event_data adapters any?}
    O -->|YES| P[Use explicit adapters BYPASS rules]
    
    P --> Q[Write to adapters]
    Q --> R[Event stored successfully]
    
    style A fill:#e3f2fd
    style R fill:#c8e6c9
```

**Example:**
```ruby
class Events::UserLogin < E11y::Event::Base
  severity :info  # No audit_event, no explicit adapters
  schema { required(:user_id).filled(:integer) }
end

# Flow: severity :info → adapters_for_severity(:info) → [:logs]
# Result: Event written to :logs adapter
```

---

## Flow 2: Audit Event with Routing Rules

Audit event without explicit adapters uses routing rules. MUST match a rule!

```mermaid
flowchart TD
    A[Track audit event] --> B[Event::Base#adapters]
    B --> C{Has explicit adapters?}
    C -->|NO| D{Is audit_event?}
    D -->|YES| E[Return empty array]
    
    E --> F[Enter Pipeline]
    F --> G[Middleware processing]
    G --> H[Routing Middleware]
    
    H --> I{event_data adapters any?}
    I -->|NO empty array| J[apply_routing_rules]
    
    J --> K[Evaluate routing_rules]
    K --> L[Rule 1: if audit_event]
    L --> M{Matches?}
    M -->|YES| N[Set routing_used_fallback = false]
    N --> O[Return :audit_encrypted]
    
    O --> P[validate_audit_routing!]
    P --> Q{Has explicit adapters?}
    Q -->|NO| R{routing_used_fallback?}
    R -->|FALSE| S[Validation PASS - rule matched]
    
    S --> T[Write to :audit_encrypted]
    T --> U[Event encrypted and stored]
    
    style A fill:#fff9c4
    style U fill:#c8e6c9
    style S fill:#c8e6c9
```

**Example:**
```ruby
class Events::UserDeleted < E11y::Event::Base
  audit_event true  # No explicit adapters
  schema { required(:user_id).filled(:integer) }
end

E11y.configure do |config|
  config.routing_rules = [
    ->(e) { :audit_encrypted if e[:audit_event] }
  ]
end

# Flow: audit_event? YES → [] → routing rule matches → :audit_encrypted
```

---

## Flow 3: Audit Event with Explicit Adapters

Audit event with explicit adapters bypasses routing rules.

```mermaid
flowchart TD
    A[Track audit event] --> B[Event::Base#adapters]
    B --> C{Has explicit adapters?}
    C -->|YES| D[Return :audit_encrypted]
    
    D --> E[Enter Pipeline]
    E --> F[Middleware processing]
    F --> G[Routing Middleware]
    
    G --> H{event_data adapters any?}
    H -->|YES| I[Use explicit adapters]
    I --> J[BYPASS routing rules]
    
    J --> K[validate_audit_routing!]
    K --> L{Has explicit adapters?}
    L -->|YES| M[Validation PASS]
    
    M --> N[Write to :audit_encrypted]
    N --> O[Event encrypted and stored]
    
    style A fill:#fff9c4
    style O fill:#c8e6c9
    style M fill:#c8e6c9
    style J fill:#ffe0b2
```

**Example:**
```ruby
class Events::UserDeleted < E11y::Event::Base
  audit_event true
  adapters :audit_encrypted  # Explicit!
  schema { required(:user_id).filled(:integer) }
end

# Flow: audit_event? YES, adapters set → [:audit_encrypted] → bypass rules
```

---

## Flow 4: Audit Event MISCONFIGURED - ERROR!

Audit event without routing - COMPLIANCE VIOLATION!

```mermaid
flowchart TD
    A[Track audit event] --> B[Event::Base#adapters]
    B --> C{Has explicit adapters?}
    C -->|NO| D{Is audit_event?}
    D -->|YES| E[Return empty array]
    
    E --> F[Enter Pipeline]
    F --> G[Routing Middleware]
    G --> H{event_data adapters any?}
    H -->|NO| I[apply_routing_rules]
    
    I --> J[Evaluate routing_rules]
    J --> K[Rule 1: if event_name = Other]
    K --> L{Matches?}
    L -->|NO| M[Set routing_used_fallback = TRUE]
    M --> N[Return fallback_adapters]
    
    N --> O[validate_audit_routing!]
    O --> P{Has explicit adapters?}
    P -->|NO| Q{routing_used_fallback?}
    Q -->|TRUE| R[RAISE ERROR]
    
    R --> S[E11y::Error: CRITICAL no routing!]
    S --> T[Event NOT stored]
    
    style A fill:#fff9c4
    style T fill:#ffcdd2
    style R fill:#ef5350
    style S fill:#ef5350
```

**Error message:**
```
CRITICAL: Audit event has no routing configuration!
Event: Events::UserDeleted
Routed to: [:stdout] (fallback adapters)

Fix options:
1. Add explicit adapters: adapters :audit_encrypted
2. Configure routing rule: config.routing_rules = [->(e) { :audit_encrypted if e[:audit_event] }]
```

---

## Flow 5: Multi-Adapter Routing

Event can go to MULTIPLE adapters simultaneously.

```mermaid
flowchart TD
    A[Track error event] --> B[Event::Base#adapters]
    B --> C{Has explicit adapters?}
    C -->|YES| D[Return :logs, :sentry]
    
    D --> E[Enter Pipeline]
    E --> F[Routing Middleware]
    F --> G[Write to EACH adapter]
    
    G --> H[adapter :logs]
    G --> I[adapter :sentry]
    
    H --> J[Loki.write event_data]
    I --> K[Sentry.write event_data]
    
    J --> L[Both writes succeed]
    K --> L
    L --> M[Event stored in 2 places]
    
    style A fill:#ffebee
    style M fill:#c8e6c9
```

**Example:**
```ruby
class Events::CriticalError < E11y::Event::Base
  severity :error
  adapters :logs, :sentry  # Multiple!
  schema { required(:error).filled(:string) }
end

# Flow: explicit [:logs, :sentry] → writes to BOTH adapters
```

---

## Flow 6: Routing Rules Priority

Multiple rules evaluated in order, first match wins.

```mermaid
flowchart TD
    A[apply_routing_rules] --> B[Evaluate Rule 1]
    B --> C{audit_event?}
    C -->|YES| D[Return :audit_encrypted]
    C -->|NO| E[Evaluate Rule 2]
    
    E --> F{retention > 90 days?}
    F -->|YES| G[Return :archive]
    F -->|NO| H[Evaluate Rule 3]
    
    H --> I{severity = error?}
    I -->|YES| J[Return :sentry]
    I -->|NO| K[No rules matched]
    
    K --> L[Use fallback_adapters]
    
    D --> M[Set routing_used_fallback = false]
    G --> M
    J --> M
    L --> N[Set routing_used_fallback = true]
    
    M --> O[Return matched adapter]
    N --> P[Return fallback adapter]
    
    style D fill:#c8e6c9
    style G fill:#c8e6c9
    style J fill:#c8e6c9
    style L fill:#fff59d
```

**Configuration:**
```ruby
E11y.configure do |config|
  config.routing_rules = [
    # Priority 1: Audit events
    ->(e) { :audit_encrypted if e[:audit_event] },
    
    # Priority 2: Long retention
    ->(e) {
      days = (Time.parse(e[:retention_until]) - Time.now) / 86400
      :archive if days > 90
    },
    
    # Priority 3: Errors
    ->(e) { :sentry if e[:severity] == :error }
  ]
end
```

---

## Flow 7: Complete Pipeline with Routing

Full picture from track() to adapter.write().

```mermaid
flowchart TD
    A[Event.track payload] --> B[Build event_data hash]
    
    B --> C[Add adapters field]
    C --> D{Event type?}
    
    D -->|Regular| E[Severity-based adapters]
    D -->|Audit no explicit| F[Empty array]
    D -->|Audit with explicit| G[Explicit adapters]
    D -->|Has explicit| G
    
    E --> H[Enter Pipeline]
    F --> H
    G --> H
    
    H --> I[TraceContext Middleware]
    I --> J[Validation Middleware]
    J --> K[PIIFilter Middleware]
    K --> L[AuditSigning Middleware]
    L --> M[Sampling Middleware]
    M --> N[Routing Middleware]
    
    N --> O{Has explicit adapters?}
    O -->|YES| P[Use explicit]
    O -->|NO| Q[Apply routing rules]
    
    Q --> R{Rule matched?}
    R -->|YES| S[Use rule result]
    R -->|NO| T[Use fallback]
    
    P --> U[Validate if audit]
    S --> U
    T --> U
    
    U --> V{Is audit + used fallback?}
    V -->|YES| W[RAISE ERROR]
    V -->|NO| X[Write to adapters]
    
    X --> Y[Event stored]
    W --> Z[Event NOT stored]
    
    style A fill:#e3f2fd
    style Y fill:#c8e6c9
    style Z fill:#ffcdd2
    style W fill:#ef5350
```

---

## Decision Matrix: What Happens to My Event?

```mermaid
flowchart TD
    Start{What type of event?}
    
    Start -->|Regular Event| R1{Has explicit adapters?}
    Start -->|Audit Event| A1{Has explicit adapters?}
    
    R1 -->|YES| R2[Use explicit adapters]
    R1 -->|NO| R3[Use severity mapping]
    
    R3 --> R4[info → logs]
    R3 --> R5[error → logs + errors_tracker]
    
    R2 --> R6[Write to adapters]
    R4 --> R6
    R5 --> R6
    R6 --> R7[SUCCESS]
    
    A1 -->|YES| A2[Use explicit adapters]
    A1 -->|NO| A3[Return empty array]
    
    A3 --> A4{Routing rule matches?}
    A4 -->|YES| A5[Use rule result]
    A4 -->|NO| A6[Would use fallback]
    
    A2 --> A7[Validation: PASS explicit]
    A5 --> A8[Validation: PASS rule matched]
    A6 --> A9[Validation: FAIL]
    
    A7 --> A10[Write to adapters]
    A8 --> A10
    A9 --> A11[RAISE ERROR]
    
    A10 --> A12[SUCCESS encrypted + signed]
    A11 --> A13[FAILURE event not stored]
    
    style R7 fill:#c8e6c9
    style A12 fill:#c8e6c9
    style A13 fill:#ffcdd2
    style A11 fill:#ef5350
```

---

## Adapter Resolution Logic

How `Event::Base#adapters` method works.

```mermaid
flowchart TD
    A[Event.track called] --> B[Event::Base#adapters method]
    
    B --> C{Check @adapters instance variable}
    C -->|SET| D[Return @adapters]
    C -->|NIL| E{Check parent class @adapters}
    
    E -->|SET| F[Return parent.adapters]
    E -->|NIL| G{Call resolved_adapters}
    
    G --> H{Is audit_event?}
    H -->|YES| I[Return empty array]
    H -->|NO| J[Call adapters_for_severity]
    
    J --> K[Check severity level]
    K --> L[severity :info → logs]
    K --> M[severity :error → logs + errors_tracker]
    K --> N[severity :fatal → logs + errors_tracker]
    K --> O[default → logs]
    
    D --> P[Result: adapters array]
    F --> P
    I --> P
    L --> P
    M --> P
    N --> P
    O --> P
    
    style I fill:#fff9c4
    style P fill:#e0e0e0
```

---

## Validation Flow for Audit Events

What happens in `validate_audit_routing!`.

```mermaid
flowchart TD
    A[validate_audit_routing! called] --> B{Is audit_event?}
    B -->|NO| C[Skip validation immediately]
    C --> D[Return - no check needed]
    
    B -->|YES| E{Has explicit adapters?}
    E -->|YES| F[Validation PASS]
    F --> G[Continue pipeline]
    
    E -->|NO| H{Check routing_used_fallback flag}
    H -->|FALSE rule matched| I[Validation PASS]
    I --> G
    
    H -->|TRUE used fallback| J[RAISE E11y::Error]
    J --> K[Build error message]
    K --> L[Include event name]
    K --> M[Include fallback adapters used]
    K --> N[Include fix option 1: explicit]
    K --> O[Include fix option 2: routing rule]
    
    L --> P[Throw exception]
    M --> P
    N --> P
    O --> P
    
    P --> Q[Event NOT written]
    Q --> R[User sees error]
    
    style C fill:#e1bee7
    style F fill:#c8e6c9
    style I fill:#c8e6c9
    style J fill:#ef5350
    style Q fill:#ffcdd2
    style R fill:#ffcdd2
```

---

## Severity-Based Adapter Mapping

Default configuration for regular events.

```mermaid
flowchart LR
    A[Event Severity] --> B{Severity Level}
    
    B -->|:debug| C[logs]
    B -->|:info| D[logs]
    B -->|:warn| E[logs]
    B -->|:error| F[logs + errors_tracker]
    B -->|:fatal| G[logs + errors_tracker]
    B -->|default| H[logs]
    
    style F fill:#ffebee
    style G fill:#ffcdd2
```

**Configuration:**
```ruby
# Default mapping (in E11y::Configuration)
{
  error: [:logs, :errors_tracker],
  fatal: [:logs, :errors_tracker],
  default: [:logs]
}
```

---

## Quick Reference Table

| Event Type | Explicit Adapters | Routing Rule | Result |
|------------|------------------|--------------|---------|
| Regular | ✅ YES | N/A | Use explicit |
| Regular | ❌ NO | ✅ Matches | Use rule result |
| Regular | ❌ NO | ❌ No match | Use fallback ✅ OK |
| Audit | ✅ YES | N/A | Use explicit |
| Audit | ❌ NO | ✅ Matches | Use rule result |
| Audit | ❌ NO | ❌ No match | ❌ ERROR! |

---

## Common Patterns

### Pattern 1: Simple Application Event

```ruby
class Events::UserLogin < E11y::Event::Base
  severity :info
  schema { required(:user_id).filled(:integer) }
end

# Flow: severity :info → [:logs] → Loki adapter
```

### Pattern 2: Error Event to Multiple Destinations

```ruby
class Events::PaymentFailed < E11y::Event::Base
  severity :error
  adapters :logs, :sentry  # Explicit multi-adapter
  schema { required(:order_id).filled(:integer) }
end

# Flow: explicit [:logs, :sentry] → both adapters
```

### Pattern 3: Audit Event via Rules

```ruby
class Events::UserDeleted < E11y::Event::Base
  audit_event true
  schema { required(:user_id).filled(:integer) }
end

# Config: routing_rules = [->(e) { :audit_encrypted if e[:audit_event] }]
# Flow: [] → rule matches → :audit_encrypted
```

### Pattern 4: High-Value Event with Long Retention

```ruby
class Events::OrderPlaced < E11y::Event::Base
  severity :info
  retention_period 7.years
  schema { required(:order_id).filled(:integer) }
end

# Config: routing_rules = [->(e) { 
#   days = (Time.parse(e[:retention_until]) - Time.now) / 86400
#   :archive if days > 365
# }]
# Flow: [] → retention rule matches → :archive
```

---

## Testing Your Routing

### Check Event Configuration

```ruby
# What adapters will this event use?
Events::UserLogin.adapters
# => [:logs]

Events::UserDeleted.adapters  # audit_event true
# => []

Events::PaymentFailed.adapters  # explicit
# => [:logs, :sentry]
```

### Test Routing Rule

```ruby
event_data = {
  event_name: "Events::UserDeleted",
  audit_event: true,
  severity: :info,
  retention_until: (Time.now + 7.years).iso8601
}

E11y.config.routing_rules.each do |rule|
  result = rule.call(event_data)
  puts "Rule result: #{result.inspect}"
end
```

### Verify in Tests

```ruby
RSpec.describe Events::UserDeleted do
  it "routes to audit_encrypted" do
    event = described_class.track(user_id: 123)
    expect(event[:routing][:adapters]).to eq([:audit_encrypted])
  end
end
```

---

## Troubleshooting

### "CRITICAL: Audit event has no routing configuration!"

**Problem:** Audit event doesn't match any routing rule.

**Solutions:**
1. Add explicit adapter: `adapters :audit_encrypted`
2. Add routing rule: `config.routing_rules = [->(e) { :audit_encrypted if e[:audit_event] }]`

### "Event not appearing in logs"

**Check:**
1. Is E11y enabled? `E11y.config.enabled`
2. What adapters configured? `E11y.config.adapters.keys`
3. What adapters will event use? `YourEvent.adapters`
4. Is sampling dropping it? Check sample_rate

### "Event going to wrong adapter"

**Debug:**
1. Check explicit adapters: `YourEvent.adapters`
2. Check routing rules: `E11y.config.routing_rules`
3. Check fallback: `E11y.config.fallback_adapters`
4. Check priority: explicit > rules > fallback

---

## Related Files

- **Fix Documentation:** `AUDIT-TRAIL-FIX.md`
- **Quick Reference:** `AUDIT-ROUTING-QUICK-REFERENCE.md`
- **Test Specs:** `spec/integration/audit*.rb`
- **Routing Middleware:** `lib/e11y/middleware/routing.rb`
- **Event Base:** `lib/e11y/event/base.rb`
