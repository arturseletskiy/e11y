# frozen_string_literal: true

module E11y
  module Metrics
    # Universal label relabeling mechanism via DSL.
    #
    # Transforms high-cardinality label values into low-cardinality categories
    # to prevent metric explosions while preserving signal quality.
    #
    # @example HTTP status codes to classes
    #   relabeler = Relabeling.new
    #   relabeler.define(:http_status) do |value|
    #     case value.to_i
    #     when 100..199 then '1xx'
    #     when 200..299 then '2xx'
    #     when 300..399 then '3xx'
    #     when 400..499 then '4xx'
    #     when 500..599 then '5xx'
    #     else 'unknown'
    #     end
    #   end
    #
    #   relabeler.apply(:http_status, 200) # => '2xx'
    #   relabeler.apply(:http_status, 404) # => '4xx'
    #
    # @example Path normalization
    #   relabeler.define(:path) do |value|
    #     value.gsub(/\/\d+/, '/:id')
    #          .gsub(/\/[a-f0-9-]{36}/, '/:uuid')
    #   end
    #
    #   relabeler.apply(:path, '/users/123/orders/456') # => '/users/:id/orders/:id'
    #
    # @example Region grouping
    #   relabeler.define(:region) do |value|
    #     case value.to_s
    #     when /^us-/ then 'us'
    #     when /^eu-/ then 'eu'
    #     when /^ap-/ then 'ap'
    #     else 'other'
    #     end
    #   end
    #
    # @see ADR-002 §4.6 (Relabeling Rules)
    class Relabeling
      # Initialize relabeler with optional rules
      #
      # @param rules [Hash{Symbol => Proc}] Initial relabeling rules
      def initialize(rules = {})
        @rules = {}
        @mutex = Mutex.new
        rules.each { |label_key, block| define(label_key, &block) }
      end

      # Define relabeling rule for a label
      #
      # Rule is applied via block that receives original value
      # and returns transformed value.
      #
      # @param label_key [Symbol, String] Label key to relabel
      # @yield [value] Block that transforms label value
      # @yieldparam value [Object] Original label value
      # @yieldreturn [String, Symbol] Transformed label value
      # @return [void]
      #
      # @example Simple mapping
      #   relabeler.define(:environment) do |value|
      #     value == 'production' ? 'prod' : 'non-prod'
      #   end
      #
      # @example Range-based classification
      #   relabeler.define(:duration_ms) do |value|
      #     case value.to_i
      #     when 0..100 then 'fast'
      #     when 101..1000 then 'medium'
      #     else 'slow'
      #     end
      #   end
      def define(label_key, &block)
        raise ArgumentError, "Block required for relabeling rule" unless block_given?

        @mutex.synchronize do
          @rules[label_key.to_sym] = block
        end
      end

      # Apply relabeling to label value
      #
      # If rule exists for label_key, applies transformation.
      # Otherwise returns original value unchanged.
      #
      # Thread-safe operation.
      #
      # @param label_key [Symbol, String] Label key
      # @param value [Object] Original value
      # @return [Object] Relabeled value or original if no rule defined
      def apply(label_key, value)
        rule = @mutex.synchronize { @rules[label_key.to_sym] }
        return value unless rule

        begin
          rule.call(value)
        rescue StandardError => e
          warn "[E11y] Relabeling error for #{label_key}=#{value}: #{e.message}"
          value # Return original on error
        end
      end

      # Apply relabeling to hash of labels
      #
      # Transforms all labels that have defined rules.
      # Labels without rules pass through unchanged.
      #
      # @param labels [Hash] Hash of label_key => value
      # @return [Hash] Hash with relabeled values
      #
      # @example
      #   labels = { http_status: 200, path: '/users/123', env: 'production' }
      #   relabeler.apply_all(labels)
      #   # => { http_status: '2xx', path: '/users/:id', env: 'production' }
      def apply_all(labels)
        labels.transform_keys(&:to_sym).transform_values do |value|
          label_key = begin
            labels.key(value).to_sym
          rescue StandardError
            nil
          end
          label_key ? apply(label_key, value) : value
        end
      end

      # Check if relabeling rule exists for label
      #
      # @param label_key [Symbol, String] Label key
      # @return [Boolean] true if rule defined
      def defined?(label_key)
        @mutex.synchronize { @rules.key?(label_key.to_sym) }
      end

      # Remove relabeling rule
      #
      # @param label_key [Symbol, String] Label key
      # @return [void]
      def remove(label_key)
        @mutex.synchronize { @rules.delete(label_key.to_sym) }
      end

      # Get all defined rule keys
      #
      # @return [Array<Symbol>] List of label keys with rules
      def keys
        @mutex.synchronize { @rules.keys }
      end

      # Reset all relabeling rules
      #
      # @return [void]
      def reset!
        @mutex.synchronize { @rules.clear }
      end

      # Get number of defined rules
      #
      # @return [Integer] Rule count
      def size
        @mutex.synchronize { @rules.size }
      end

      # Predefined common relabeling rules
      module CommonRules
        # HTTP status code to status class (1xx, 2xx, 3xx, 4xx, 5xx)
        #
        # @param value [Integer, String] HTTP status code
        # @return [String] Status class
        def self.http_status_class(value)
          code = value.to_i
          return "unknown" if code < 100 || code >= 600

          "#{code / 100}xx"
        end

        # Path normalization - replace numeric IDs and UUIDs with placeholders
        #
        # @param value [String] URL path
        # @return [String] Normalized path
        def self.normalize_path(value)
          value.to_s
               .gsub(%r{/[a-f0-9-]{36}}, "/:uuid") # UUIDs (must be before :id to avoid partial match)
               .gsub(%r{/[a-f0-9]{32}}, "/:hash") # MD5 hashes (must be before :id)
               .gsub(%r{/\d+}, "/:id") # /users/123 -> /users/:id
        end

        # Region to region group (us-east-1 -> us, eu-west-2 -> eu)
        #
        # @param value [String] AWS-style region
        # @return [String] Region group
        def self.region_group(value)
          case value.to_s
          when /^us-/ then "us"
          when /^eu-/ then "eu"
          when /^ap-/ then "ap"
          when /^sa-/ then "sa"
          when /^ca-/ then "ca"
          when /^af-/ then "af"
          when /^me-/ then "me"
          else "other"
          end
        end

        # Duration classification (ms to fast/medium/slow)
        #
        # @param value [Numeric] Duration in milliseconds
        # @return [String] Classification
        def self.duration_class(value)
          ms = value.to_f
          case ms
          when 0..100 then "fast"
          when 101..1000 then "medium"
          when 1001..5000 then "slow"
          else "very_slow"
          end
        end
      end
    end
  end
end
