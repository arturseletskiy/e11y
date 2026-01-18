# frozen_string_literal: true

require_relative "lib/e11y/version"

Gem::Specification.new do |spec|
  spec.name = "e11y"
  spec.version = E11y::VERSION
  spec.authors = ["Artur Seletskiy"]

  spec.summary = "E11y - Easy Telemetry: Production-grade observability for Rails with zero-config SLO tracking"
  spec.description = <<~DESC
    E11y (Easy Telemetry) - production-ready observability gem for Ruby on Rails applications.

    KEY FEATURES:
    • 📊 Zero-Config SLO Tracking - automatic Service Level Objectives for HTTP endpoints and background jobs
    • 🎯 Request-Scoped Debug Buffering - buffer debug logs in memory, flush only on errors (reduce log noise by 90%)
    • 📈 Pattern-Based Metrics - auto-generate Prometheus/Yabeda metrics from business events
    • 🔒 GDPR/SOC2 Compliance - built-in PII filtering and audit trails
    • 🔌 Pluggable Adapters - send events to Loki, Sentry, OpenTelemetry, Elasticsearch, or custom backends
    • 🚀 High Performance - zero-allocation event tracking, lock-free ring buffers, adaptive memory limits
    • 🧵 Thread-Safe - designed for multi-threaded Rails apps and Sidekiq workers
    • 🎭 Multi-Tenant Ready - trace context propagation across services with OpenTelemetry integration
    • 📝 Type-Safe Events - declarative event schemas with dry-schema validation
    • ⚡ Rate Limiting & Sampling - protect production from metric storms and cost overruns

    Perfect for SuperApp architectures, microservices, and high-scale Rails applications.
    Battle-tested patterns from Devise, Sidekiq, Sentry, and Yabeda.
  DESC
  spec.homepage = "https://github.com/arturseletskiy/e11y"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/arturseletskiy/e11y"
  spec.metadata["changelog_uri"] = "https://github.com/arturseletskiy/e11y/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://github.com/arturseletskiy/blob/main/e11y/docs"
  spec.metadata["bug_tracker_uri"] = "https://github.com/arturseletskiy/e11y/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile docs/researches/])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "activesupport", ">= 7.0"
  spec.add_dependency "concurrent-ruby", "~> 1.2" # Thread-safe data structures
  spec.add_dependency "dry-schema", "~> 1.13" # Event schema validation
  spec.add_dependency "dry-types", "~> 1.7"
  spec.add_dependency "zeitwerk", "~> 2.6"

  # Development dependencies
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "rubocop", "~> 1.50"
  spec.add_development_dependency "rubocop-rake", "~> 0.6"
  spec.add_development_dependency "rubocop-rspec", "~> 2.22"
  spec.add_development_dependency "simplecov", "~> 0.22"
  spec.add_development_dependency "webmock", "~> 3.19" # For HTTP adapter testing
  spec.add_development_dependency "yard", "~> 0.9"

  # Optional adapter dependencies (install only if using specific adapters)
  # LokiAdapter: gem install faraday
  # SentryAdapter: gem install sentry-ruby
  spec.add_development_dependency "faraday", "~> 2.7" # For LokiAdapter
  spec.add_development_dependency "sentry-ruby", "~> 5.15" # For SentryAdapter
end
