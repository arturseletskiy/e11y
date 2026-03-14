# frozen_string_literal: true

# Integration test helpers for checking service availability and dependencies
module IntegrationHelpers
  # Check if a gem/constant is available
  #
  # @param constant_name [String] Name of constant to check (e.g., "Faraday", "OpenTelemetry")
  # @return [Boolean] true if constant is defined
  def dependency_available?(constant_name)
    Object.const_defined?(constant_name)
  rescue NameError
    false
  end

  # Check if a service is available via HTTP
  #
  # @param url [String] Service URL to check
  # @param timeout [Integer] Timeout in seconds (default: 5)
  # @param health_path [String] Health check path (default: "/")
  # @return [Boolean] true if service responds
  def service_available?(url, timeout: 5, health_path: nil)
    require "net/http"
    require "uri"

    uri = URI(url)

    # Use specific health check path if provided, otherwise use URL path or "/"
    check_path = health_path || uri.path
    check_path = "/" if check_path.empty?

    # Integration tests use real services - no WebMock needed
    begin
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = timeout
      http.read_timeout = timeout

      http.start do |h|
        # Try HEAD first, fallback to GET if HEAD not supported

        response = h.head(check_path)
        response.code.to_i < 500
      rescue StandardError
        # Some services don't support HEAD, try GET
        response = h.get(check_path)
        response.code.to_i < 500
      end
    rescue StandardError
      false
    end
  end

  # Require a dependency or raise a helpful error
  #
  # @param constant_name [String] Name of constant to require
  # @param gem_name [String] Name of gem to install (optional)
  # @raise [RuntimeError] if dependency is not available
  def require_dependency!(constant_name, gem_name: nil)
    # Try to require the gem first if gem_name provided
    if gem_name
      begin
        require gem_name.downcase
      rescue LoadError
        # Gem not installed
      end
    end

    return if dependency_available?(constant_name)

    message = "Required dependency '#{constant_name}' is not available."
    message += "\nInstall with: bundle install --with integration" if gem_name
    message += "\nOr install gem: gem install #{gem_name}" if gem_name && !gem_name.empty?
    message += "\n\nIn CI, ensure integration dependencies are installed."
    raise message
  end

  SERVICE_HEALTH_PATHS = {
    "loki" => "/ready",
    "prometheus" => "/-/healthy",
    "elasticsearch" => "/_cluster/health"
  }.freeze

  # Require a service to be available or raise a helpful error
  #
  # @param service_name [String] Name of service (for error message)
  # @param url [String] Service URL to check
  # @param env_var [String] Environment variable name (optional)
  # @param health_path [String] Health check path (optional, defaults to URL path or "/")
  # @raise [RuntimeError] if service is not available
  def require_service!(service_name, url: nil, env_var: nil, health_path: nil)
    url ||= ENV.fetch(env_var, nil) if env_var

    # Use service-specific health check paths
    health_path ||= SERVICE_HEALTH_PATHS[service_name.downcase]

    return if url && service_available?(url, health_path: health_path)

    message = "Required service '#{service_name}' is not available."
    message += "\nURL: #{url}" if url
    message += "\nHealth check path: #{health_path}" if health_path
    message += "\n\nIn local development, start services with: docker-compose up -d"
    message += "\nIn CI, ensure services are configured in GitHub Actions."
    raise message
  end

  # Skip example if service is not available (graceful skip vs require_service! which raises)
  #
  # @param service_name [String] Name of service (for skip message)
  # @param url [String] Service URL to check
  # @param env_var [String] Environment variable name (optional)
  # @param health_path [String] Health check path (optional)
  # @return [void] Skips the example if service unavailable
  def skip_unless_service!(service_name, url: nil, env_var: nil, health_path: nil)
    url ||= ENV.fetch(env_var, nil) if env_var
    health_path ||= SERVICE_HEALTH_PATHS[service_name.downcase]

    return if url && service_available?(url, health_path: health_path)

    skip "Service '#{service_name}' not available at #{url}. Start with: docker compose up -d #{service_name.downcase}"
  end

  # Check if we're running in CI environment
  #
  # @return [Boolean] true if CI environment detected
  def ci?
    ENV["CI"] == "true" || ENV["GITHUB_ACTIONS"] == "true"
  end

  # Get service URL from environment or use default
  #
  # @param env_var [String] Environment variable name
  # @param default [String] Default URL if env var not set
  # @return [String] Service URL
  def service_url(env_var, default)
    ENV[env_var] || default
  end

  # Find events in memory adapter by class or normalized event name
  #
  # This helper handles the fact that event_name may or may not be normalized by Versioning middleware
  # (Versioning is opt-in). It searches by both normalized event_name, original event_name, and event_class.
  #
  # @param memory_adapter [E11y::Adapters::InMemory] Memory adapter instance
  # @param event_class [Class, String] Event class or class name (e.g., Events::TestEvent or "Events::TestEvent")
  # @param normalized_name [String, nil] Optional normalized event name (e.g., "test.event")
  # @return [Array<Hash>] Matching events
  #
  # @example
  #   events = find_events_by_class(memory_adapter, Events::TestEvent)
  #   events = find_events_by_class(memory_adapter, "Events::TestEvent", normalized_name: "test.event")
  def find_events_by_class(memory_adapter, event_class, normalized_name: nil)
    events = memory_adapter.events

    # Get class name for matching
    class_name = event_class.is_a?(Class) ? event_class.name : event_class.to_s

    # Calculate normalized name if not provided
    normalized_name ||= normalize_event_name_for_testing(class_name)

    # Search by:
    # 1. Normalized event_name (if Versioning middleware is enabled)
    # 2. Original event_name (class name, if Versioning middleware is NOT enabled)
    # 3. event_class object match
    # 4. event_class name match
    events.select do |e|
      e[:event_name] == normalized_name ||
        e[:event_name] == class_name ||
        e[:event_name]&.include?(normalized_name) ||
        e[:event_name]&.include?(class_name) ||
        (event_class.is_a?(Class) && e[:event_class] == event_class) ||
        (event_class.is_a?(String) && e[:event_class]&.name == event_class)
    end
  end

  # Normalize event name for testing (same logic as Versioning middleware)
  #
  # @param class_name [String] Event class name (e.g., "Events::TestEvent")
  # @return [String] Normalized name (e.g., "test.event")
  def normalize_event_name_for_testing(class_name)
    return class_name unless class_name

    # Remove "Events::" namespace prefix
    name = class_name.sub(/^Events::/, "")
    # Remove version suffix (V2, V3, etc.)
    name = name.sub(/V\d+$/, "")
    # Convert nested namespaces to dots
    name = name.gsub("::", ".")
    # Convert to snake_case then dots
    name.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2') # ABCWord → ABC_Word
        .gsub(/([a-z\d])([A-Z])/, '\1_\2') # wordWord → word_Word
        .downcase
        .tr("_", ".") # Convert underscores to dots
  end
end

RSpec.configure do |config|
  config.include IntegrationHelpers
end
