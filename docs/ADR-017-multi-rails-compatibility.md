# ADR-017: Multi-Rails Version Compatibility

**Status:** Accepted  
**Date:** January 26, 2026  
**Covers:** Cross-cutting concern  
**Depends On:** ADR-008 (Rails Integration)

---

## Context & Problem

E11y initially supported only Rails 8.0, limiting adoption:
- ~40% of Rails apps still on 7.x
- Enterprise upgrades take 12-18 months
- No migration path for Rails 7 users

---

## Decision

Support Rails 7.0, 7.1, 8.0 with dynamic version detection.

**Implementation:**

```ruby
# Gemfile
rails_version = ENV.fetch('RAILS_VERSION', '8.0')
gem 'rails', "~> #{rails_version}.0", "< 8.1"

if rails_version.to_f < 8.0
  gem 'sqlite3', '~> 1.4' # Rails 7.x
else
  gem 'sqlite3', '~> 2.0' # Rails 8.x
end
```

**CI Matrix:**
```yaml
matrix:
  ruby: ['3.2', '3.3']
  rails: ['7.0', '7.1', '8.0']
# Total: 6 combinations
```

---

## Consequences

### Positive
- Doubles potential user base
- Enterprise-friendly (slower upgrade cycles)
- Migration path (use E11y during Rails upgrade)
- Full feature parity (no degradation)

### Negative
- CI time: 5min → 15min (3× Rails versions)
- Maintenance: 3 Rails versions to test
- Conditional code (2 places only)

---

## Version-Specific Code

**1. Exception handling (Rails 8.0 changed behavior):**
```ruby
if Rails.version.to_f >= 8.0
  expect(response.status).to eq(500) # Rails 8.0: caught
else
  expect { get '/error' }.to raise_error # Rails 7.x: raised
end
```

**2. sqlite3 dependency (Gemfile only)**

---

## Maintenance Plan

**Drop Rails 7.0 when:**
- Rails 7.0 EOL (~2027)
- <5% users on Rails 7.0
- Rails 9.0 released

**Review quarterly:** Check market share, update CI matrix.

---

## Alternatives Considered

1. **Rails 8.0 only** - Rejected: excludes 40% users
2. **Rails 6.x support** - Rejected: EOL June 2024
3. **Backport gem** - Rejected: doubles maintenance

---

## Success Metrics

| Metric | Target | Current |
|--------|--------|---------|
| Test pass rate | 100% | 100% ✅ |
| Code coverage | ≥95% | 96.46% ✅ |
| Version checks | <10 | 2 ✅ |
| CI time | <20min | ~15min ✅ |
