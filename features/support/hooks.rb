# frozen_string_literal: true

# features/support/hooks.rb
#
# Global Cucumber hooks that apply to every scenario unless tagged otherwise.

# Capture the canonical test pipeline middleware list once, immediately after
# env.rb has finished configuring E11y. Every Before hook restores this
# snapshot so that features which mutate the pipeline (adaptive_sampling,
# event_versioning) cannot pollute subsequent features.
#
# We dup the array so that in-place mutations (reject!, insert, unshift) made
# during a scenario only affect the LIVE @middlewares array, not this snapshot.
# Individual MiddlewareEntry structs are immutable (data-only), so sharing
# references between the snapshot and the live array is safe.
INITIAL_PIPELINE_MIDDLEWARES = E11y.config.pipeline.middlewares.dup.freeze

# Railtie disables E11y in test; enable for features that need event tracking.
Before("not @rails") do
  E11y.config.enabled = true
end

# @rails scenarios verify Railtie behavior; ensure E11y stays disabled.
Before("@rails") do
  E11y.config.enabled = false
end

# Before each scenario:
#   1. Restore the pipeline to the canonical test configuration.
#   2. Invalidate the cached built_pipeline so the next Event.track() call
#      builds a fresh chain from the restored middlewares.
#   3. Clear the memory adapter so events from one scenario do not bleed
#      into the next.
Before do
  E11y.config.pipeline.instance_variable_set(:@middlewares, INITIAL_PIPELINE_MIDDLEWARES.dup)
  E11y.config.instance_variable_set(:@built_pipeline, nil)
  clear_events!
end

# After each scenario: clean the database so ActiveRecord models (e.g. Post)
# created during a scenario do not persist into the next.
After do
  ActiveRecord::Base.connection.execute("DELETE FROM posts") if ActiveRecord::Base.connection.table_exists?("posts")
end

# Before hook for @wip scenarios: print a reminder that the scenario is
# expected to FAIL (exposes a known bug).
Before("@wip") do |scenario|
  # Cucumber marks @wip scenarios as pending by default when running with
  # --wip flag. Without --wip they run normally and are expected to fail.
  # No action needed here — the tag is informational for the runner.
end

# After hook for @wip scenarios: emit a warning if the scenario PASSED,
# because that would mean the bug was fixed and the @wip tag should be removed.
After("@wip") do |scenario|
  if scenario.passed?
    warn "\n[cucumber] WARNING: @wip scenario '#{scenario.name}' PASSED — " \
         "the underlying bug may be fixed. Remove @wip tag if confirmed.\n"
  end
end
