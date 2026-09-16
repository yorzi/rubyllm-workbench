module Ai
  class SchemaValidator
    def initialize(schema)
      @schema = schema.is_a?(SchemaDefinition) ? schema.schema : SchemaDefinition.parse(schema).schema
    end

    def errors_for(value)
      validate_node(value, @schema, "$")
    end

    private

    def validate_node(value, schema, path)
      errors = []
      type = schema["type"]

      case type
      when "object"
        unless value.is_a?(Hash)
          errors << "#{path} must be an object"
          return errors
        end

        properties = schema.fetch("properties", {})
        schema.fetch("required", []).each do |name|
          errors << "#{path}.#{name} is required" unless value.key?(name) || value.key?(name.to_sym)
        end
        if schema.fetch("additionalProperties", false) == false
          unknown = value.keys.map(&:to_s) - properties.keys
          errors.concat(unknown.map { |name| "#{path}.#{name} is not allowed" })
        end
        properties.each do |name, child_schema|
          child_value = if value.key?(name)
            value[name]
          else
            value[name.to_sym]
          end
          next if child_value.nil? && !value.key?(name) && !value.key?(name.to_sym)

          errors.concat(validate_node(child_value, child_schema, "#{path}.#{name}"))
        end
      when "array"
        unless value.is_a?(Array)
          errors << "#{path} must be an array"
          return errors
        end

        value.each_with_index do |item, index|
          errors.concat(validate_node(item, schema.fetch("items"), "#{path}[#{index}]"))
        end
      when "string"
        errors << "#{path} must be a string" unless value.is_a?(String)
      when "number"
        errors << "#{path} must be a number" unless value.is_a?(Numeric)
      when "integer"
        errors << "#{path} must be an integer" unless value.is_a?(Integer)
      when "boolean"
        errors << "#{path} must be a boolean" unless [ true, false ].include?(value)
      end

      if schema.key?("enum") && !schema.fetch("enum").include?(value)
        errors << "#{path} must be one of #{schema.fetch("enum").map(&:inspect).join(", ")}"
      end

      errors
    end
  end
end
