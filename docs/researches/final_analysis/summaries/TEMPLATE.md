# [UC/ADR]-XXX: [Name] - Summary

**Document:** [UC-XXX / ADR-XXX]  
**Created:** [Date]  
**Analyzed by:** Agent  
**Priority:** [Critical / Important / Standard]  
**Domain:** [Core / Integration / Security / Performance / DX]

---

## 📋 Quick Reference

| Property | Value |
|----------|-------|
| **Type** | [Use Case / Architectural Decision] |
| **Complexity** | [Simple / Medium / Complex] |
| **Dependencies** | [List related UCs/ADRs] |
| **Contradictions** | [Number found] |

---

## 🎯 Purpose & Problem Statement

**What problem does this solve?**
[1-2 sentences describing the core problem]

**Who is affected?**
[Ruby developers / DevOps / Product teams / End users]

**Expected outcome:**
[What success looks like]

---

## 📝 Key Requirements

### Must Have (Critical)
- [ ] Requirement 1
- [ ] Requirement 2
- [ ] Requirement 3

### Should Have (Important)
- [ ] Optional requirement 1
- [ ] Optional requirement 2

### Could Have (Nice to have)
- [ ] Future enhancement 1

---

## 🔗 Dependencies

### Related Use Cases
- **UC-XXX:** [Name] - [Relationship description]
- **UC-YYY:** [Name] - [Relationship description]

### Related ADRs
- **ADR-XXX:** [Decision] - [Why related]
- **ADR-YYY:** [Decision] - [Why related]

### External Dependencies
- [Gem / Service / API]
- [Library / Framework]

---

## ⚡ Technical Constraints

### Performance
- [Latency requirement]
- [Throughput requirement]
- [Resource limits]

### Scalability
- [Horizontal scaling needs]
- [Vertical scaling considerations]

### Security
- [Security requirements]
- [Compliance needs (GDPR, PCI-DSS, etc.)]

### Compatibility
- [Ruby versions]
- [Rails versions]
- [Other dependencies]

---

## 🎭 User Story / Rationale

**As a** [role]  
**I want** [feature/capability]  
**So that** [business value]

**Rationale (for ADRs):**
[Why this architectural decision was made]

**Alternatives considered:**
1. [Alternative 1] - [Why not chosen]
2. [Alternative 2] - [Why not chosen]

**Trade-offs:**
- ✅ **Pros:** [Benefits]
- ❌ **Cons:** [Downsides]

---

## ⚠️ Potential Contradictions

### Contradiction 1: [Name]
**Conflict:** Need to [improve A] BUT [worsens B]  
**Impact:** [High / Medium / Low]  
**Related to:** [Other UCs/ADRs]  
**Notes:** [Additional context]

### Contradiction 2: [Name]
**Conflict:** [Description]  
**Impact:** [High / Medium / Low]  
**Related to:** [Other UCs/ADRs]

---

## 🔍 Implementation Notes

### Key Components
- [Component 1] - [Description]
- [Component 2] - [Description]

### Configuration Required
```ruby
# Example configuration snippet
E11y.configure do |config|
  config.feature = ...
end
```

### APIs / Interfaces
- [Class / Module]
- [Public methods]

### Data Structures
- [Models / Schemas]

---

## ❓ Questions & Gaps

### Clarification Needed
1. [Question about requirement]
2. [Question about constraint]

### Missing Information
1. [What's not documented]
2. [What needs research]

### Ambiguities
1. [Unclear aspect]
2. [Needs decision]

---

## 🧪 Testing Considerations

### Test Scenarios
1. [Happy path]
2. [Edge case 1]
3. [Error case]

### Mocking Needs
- [External service to mock]
- [Adapter to stub]

---

## 📊 Complexity Assessment

**Overall Complexity:** [Simple / Medium / Complex]

**Reasoning:**
- [Factor 1 contributing to complexity]
- [Factor 2 contributing to complexity]

**Estimated Implementation Time:**
- [Junior dev: X days]
- [Senior dev: Y days]

---

## 📚 References

### Related Documentation
- [Link to UC/ADR]
- [Link to related design doc]

### Similar Solutions
- [Other gem / library]
- [Industry pattern]

### Research Notes
- [Key insight from research]
- [Data point or benchmark]

---

## 🏷️ Tags

`#[domain]` `#[priority]` `#[complexity]` `#[feature-area]`

---

**Last Updated:** [Date]  
**Next Review:** [When to revisit this summary]
