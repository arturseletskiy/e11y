# features/smoke.feature
# Smoke test: verifies the Cucumber infrastructure boots correctly.
Feature: Cucumber infrastructure smoke test

  Background:
    Given the application is running

  Scenario: Rails app is reachable via Rack::Test
    When I send a GET request to "/posts"
    Then the response status should be 200

  Scenario: Memory adapter starts empty after Before hook
    Then the memory adapter should be empty
