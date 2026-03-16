# frozen_string_literal: true

require "yaml"

module E11y
  module SLO
    class ConfigLoader
      class << self
        def load(search_paths: default_search_paths)
          search_paths.each do |base|
            path = File.join(base.to_s, "slo.yml")
            next unless File.file?(path)

            content = File.read(path)
            return YAML.safe_load(content) || {}
          end
          nil
        end

        private

        def default_search_paths
          base = defined?(Rails) ? Rails.root.to_s : Dir.pwd
          [File.join(base, "config"), File.join(base, "config", "e11y"), Dir.pwd]
        end
      end
    end
  end
end
