module Ai
  class SchemaDefinition
    ALLOWED_DOCUMENT_KEYS = %w[name description schema strict].freeze
    ALLOWED_SCHEMA_KEYS = %w[type properties required items enum description additionalProperties].freeze
    TYPES = %w[object array string number integer boolean].freeze

    class DefinitionError < StandardError
      attr_reader :problems

      def initialize(problems)
        @problems = Array(problems)
        super(@problems.join("; "))
      end
    end

    DEFAULT_DOCUMENT = {
      "name" => "response_summary",
      "description" => "A concise summary with a confidence signal.",
      "strict" => false,
      "schema" => {
        "type" => "object",
        "properties" => {
          "summary" => { "type" => "string", "description" => "The concise answer." },
          "confidence" => { "type" => "number", "description" => "Confidence from 0 to 1." }
        },
        "required" => %w[summary confidence],
        "additionalProperties" => false
      }
    }.freeze

    class << self
      def parse(raw)
        value = raw.is_a?(String) ? JSON.parse(raw) : raw
        new(value).tap(&:validate!)
      rescue JSON::ParserError => error
        raise DefinitionError, [ "invalid JSON: #{error.message}" ]
      rescue TypeError => error
        raise DefinitionError, [ "schema must be JSON-compatible: #{error.message}" ]
      end

      def default_json
        JSON.pretty_generate(DEFAULT_DOCUMENT)
      end
    end

    attr_reader :document

    def initialize(document)
      @document = normalize(document)
    end

    def schema
      document.fetch("schema")
    end

    def name
      document.fetch("name")
    end

    def validate!
      problems = []
      unless document.is_a?(Hash)
        raise DefinitionError, [ "schema document must be an object" ]
      end

      unknown_document_keys = document.keys - ALLOWED_DOCUMENT_KEYS
      problems << "unsupported top-level keys: #{unknown_document_keys.join(", ")}" if unknown_document_keys.any?
      problems << "name must be a string" unless document["name"].is_a?(String)
      problems << "name must contain only letters, numbers, underscores, or hyphens" unless valid_name?
      problems << "schema must be an object" unless document["schema"].is_a?(Hash)
      if document.key?("description") && !document["description"].is_a?(String)
        problems << "description must be a string"
      end
      if document.key?("strict") && ![ true, false ].include?(document["strict"])
        problems << "strict must be a boolean"
      end

      problems.concat(schema_problems(schema)) if document["schema"].is_a?(Hash)
      raise DefinitionError, problems if problems.any?

      self
    end

    def payload
      validate!
      {
        name: document.fetch("name"),
        schema: schema,
        strict: document.fetch("strict", false),
        description: document["description"]
      }.compact
    end

    private

    def normalize(value)
      JSON.parse(JSON.generate(value))
    end

    def valid_name?
      name = document["name"]
      name.is_a?(String) && name.match?(/\A[a-zA-Z][a-zA-Z0-9_-]{0,63}\z/)
    end

    def schema_problems(node, path = "$")
      problems = []
      unknown_keys = node.keys - ALLOWED_SCHEMA_KEYS
      problems << "#{path}: unsupported keys: #{unknown_keys.join(", ")}" if unknown_keys.any?

      type = node["type"]
      problems << "#{path}.type must be one of #{TYPES.join(", ")}" unless TYPES.include?(type)
      problems << "#{path}.description must be a string" if node.key?("description") && !node["description"].is_a?(String)

      if node.key?("enum")
        enum = node["enum"]
        problems << "#{path}.enum must be a non-empty array" unless enum.is_a?(Array) && enum.any?
      end

      case type
      when "object"
        properties = node.fetch("properties", {})
        problems << "#{path}.properties must be an object" unless properties.is_a?(Hash)
        if properties.is_a?(Hash)
          properties.each do |property_name, property_schema|
            if property_name.to_s.empty?
              problems << "#{path}.properties contains an empty name"
            elsif !property_schema.is_a?(Hash)
              problems << "#{path}.properties.#{property_name} must be an object"
            else
              problems.concat(schema_problems(property_schema, "#{path}.properties.#{property_name}"))
            end
          end
        end

        required = node.fetch("required", [])
        problems << "#{path}.required must be an array" unless required.is_a?(Array)
        if required.is_a?(Array) && properties.is_a?(Hash)
          problems << "#{path}.required must contain only property names" unless required.all? { |name| properties.key?(name) }
        end

        additional_properties = node.fetch("additionalProperties", false)
        problems << "#{path}.additionalProperties must be a boolean" unless [ true, false ].include?(additional_properties)
      when "array"
        items = node["items"]
        problems << "#{path}.items must be an object" unless items.is_a?(Hash)
        problems.concat(schema_problems(items, "#{path}.items")) if items.is_a?(Hash)
      else
        problems << "#{path} cannot define properties" if node.key?("properties")
        problems << "#{path} cannot define items" if node.key?("items")
        problems << "#{path}.required is only valid for object schemas" if node.key?("required")
        problems << "#{path}.additionalProperties is only valid for object schemas" if node.key?("additionalProperties")
      end

      problems
    end
  end
end
