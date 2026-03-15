# frozen_string_literal: true

module E11y
  module Versioning
    # Extracts version number and base name from event class names (ADR-012 §3.2).
    #
    # @example
    #   VersionExtractor.extract_version("Events::OrderPaidV2")  # => 2
    #   VersionExtractor.extract_version("Events::OrderPaid")    # => 1
    #   VersionExtractor.extract_base_name("Events::OrderPaidV2") # => "Events::OrderPaid"
    class VersionExtractor
      VERSION_REGEX = /V(\d+)$/

      # @param class_name [String] Event class name (e.g. "Events::OrderPaidV2")
      # @return [Integer] Version number (1 if no suffix)
      def self.extract_version(class_name)
        return 1 unless class_name

        match = class_name.to_s.match(VERSION_REGEX)
        match ? match[1].to_i : 1
      end

      # @param class_name [String] Event class name
      # @return [String] Base name without version suffix (e.g. "Events::OrderPaid")
      def self.extract_base_name(class_name)
        return class_name unless class_name

        class_name.to_s.sub(VERSION_REGEX, "")
      end
    end
  end
end
