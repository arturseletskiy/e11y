# frozen_string_literal: true

# Centralized E11y test setup (ADR-011 F-004).
# Ensures unit tests have InMemory adapter; integration tests use dummy config (:memory).
RSpec.configure do |config|
  config.before do |example|
    next if example.metadata[:integration]

    cfg = E11y.configuration
    next if cfg.adapters[:test]

    cfg.adapters[:test] = E11y::Adapters::InMemoryTest.new
    cfg.fallback_adapters = [:test]
  end
end
