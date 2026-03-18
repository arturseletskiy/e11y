# frozen_string_literal: true

module E11y
  module Documentation
    # Generates Markdown documentation for registered E11y events.
    class Generator
      def self.generate(output_dir, criteria: {}, grep: nil)
        classes = criteria.any? ? E11y::Registry.where(**criteria) : E11y::Registry.event_classes
        classes = classes.select { |c| (c.respond_to?(:event_name) ? c.event_name : c.name).to_s.include?(grep) } if grep

        FileUtils.mkdir_p(output_dir)
        write_index(output_dir, classes)
        classes.each { |klass| write_event_doc(output_dir, klass) }
      end

      def self.write_index(output_dir, classes)
        lines = ["# E11y Events", "", "| Event | Class | Severity |", "|-------|-------|----------|"]
        classes.each do |klass|
          name = klass.respond_to?(:event_name) ? klass.event_name : klass.name
          sev = klass.respond_to?(:severity) ? klass.severity : "—"
          lines << "| #{name} | #{klass.name} | #{sev} |"
        end
        File.write(File.join(output_dir, "README.md"), "#{lines.join("\n")}\n")
      end

      def self.write_event_doc(output_dir, klass)
        name = klass.respond_to?(:event_name) ? klass.event_name : klass.name
        schema_keys = extract_schema_keys(klass)
        sev = klass.respond_to?(:severity) ? klass.severity : "—"
        lines = ["# #{name}", "", "- **Class:** #{klass.name}", "- **Severity:** #{sev}"]
        lines << "- **Schema keys:** #{schema_keys.join(', ')}" if schema_keys&.any?
        lines << ""
        File.write(File.join(output_dir, "#{name.to_s.tr('.', '_')}.md"), "#{lines.join("\n")}\n")
      end

      def self.extract_schema_keys(klass)
        return nil unless klass.respond_to?(:compiled_schema)

        schema = klass.compiled_schema
        return nil if schema.nil? || !schema.respond_to?(:key_map)

        schema.key_map.keys.map(&:name)
      rescue StandardError
        nil
      end
    end
  end
end
