# frozen_string_literal: true

# features/support/hooks.rb
#
# Global Cucumber hooks that apply to every scenario unless tagged otherwise.

# Before each scenario: clear the memory adapter so events from one scenario
# do not bleed into the next.
Before do
  clear_events!
end

# After each scenario: clean the database so ActiveRecord models (e.g. Post)
# created during a scenario do not persist into the next.
After do
  if ActiveRecord::Base.connection.table_exists?("posts")
    ActiveRecord::Base.connection.execute("DELETE FROM posts")
  end
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
