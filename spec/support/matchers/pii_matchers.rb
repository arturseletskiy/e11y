# frozen_string_literal: true

# Custom RSpec matchers for PII filtering tests

RSpec::Matchers.define :be_filtered do
  match do |actual|
    actual == "[FILTERED]" ||
      actual =~ /^hashed_[a-f0-9]{16}$/ ||
      actual =~ /^\[.+\]$/ # [CARD], [EMAIL], [SSN], etc.
  end

  failure_message do |actual|
    "expected #{actual.inspect} to be filtered (should be '[FILTERED]', 'hashed_*', or '[TYPE]')"
  end

  failure_message_when_negated do |actual|
    "expected #{actual.inspect} NOT to be filtered, but it was"
  end
end

RSpec::Matchers.define :be_hashed do
  match do |actual|
    actual =~ /^hashed_[a-f0-9]{16}$/
  end

  failure_message do |actual|
    "expected #{actual.inspect} to be hashed (format: hashed_[hex16])"
  end
end

RSpec::Matchers.define :be_partially_masked do
  match do |actual|
    # Pattern: "ab***yz" (first 2 + last 2 visible)
    actual =~ /^.{2}\*{3}.{2,}$/ ||
      # Or shorter: "a***z"
      actual =~ /^.\*{3}.$/
  end

  failure_message do |actual|
    "expected #{actual.inspect} to be partially masked (e.g., 'ab***yz')"
  end
end

RSpec::Matchers.define :contain_no_pii do |patterns = {}|
  match do |hash|
    @failed_checks = []
    result = check_hash_for_pii(hash, patterns)
    result
  end

  def check_hash_for_pii(obj, patterns, path = [])
    case obj
    when Hash
      obj.all? do |key, value|
        check_hash_for_pii(value, patterns, path + [key])
      end
    when Array
      obj.all?.with_index do |item, idx|
        check_hash_for_pii(item, patterns, path + ["[#{idx}]"])
      end
    when String
      !contains_pii_patterns?(obj, path)
    else
      true
    end
  end

  def contains_pii_patterns?(string, path)
    # Check for common PII patterns
    checks = {
      email: string =~ /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i,
      ssn: string =~ /\b\d{3}-\d{2}-\d{4}\b/,
      credit_card: string =~ /\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b/,
      phone: string =~ /\+?\d{1,3}[-.\s]?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}/
    }

    checks.each do |type, found|
      if found
        @failed_checks << { path: path.join("."), type: type, value: string }
        return true
      end
    end

    false
  end

  failure_message do
    lines = ["expected hash to contain no PII, but found:"]
    @failed_checks.each do |check|
      lines << "  - #{check[:type]} at #{check[:path]}: #{check[:value].inspect}"
    end
    lines.join("\n")
  end
end

RSpec::Matchers.define :preserve_structure do |original|
  match do |filtered|
    same_structure?(original, filtered)
  end

  def same_structure?(obj1, obj2, path = []) # rubocop:todo Metrics/AbcSize
    case obj1
    when Hash
      return false unless obj2.is_a?(Hash)
      return false unless obj1.keys.sort == obj2.keys.sort

      obj1.all? do |key, value|
        same_structure?(value, obj2[key], path + [key])
      end
    when Array
      return false unless obj2.is_a?(Array)
      return false unless obj1.size == obj2.size

      obj1.each.with_index.all? do |item, idx|
        same_structure?(item, obj2[idx], path + ["[#{idx}]"])
      end
    else
      true # Values can differ, we only care about structure
    end
  end

  failure_message do
    "expected filtered hash to preserve structure of original hash"
  end
end
