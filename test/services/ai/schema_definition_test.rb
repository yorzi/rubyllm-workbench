require "test_helper"

class Ai::SchemaDefinitionTest < ActiveSupport::TestCase
  test "normalizes and validates the default schema document" do
    definition = Ai::SchemaDefinition.parse(Ai::SchemaDefinition.default_json)

    assert_equal "response_summary", definition.name
    assert_equal "object", definition.schema["type"]
    assert_equal %w[summary confidence], definition.schema["required"]
    assert_equal false, definition.payload[:strict]
  end

  test "rejects unsupported schema keywords instead of evaluating them" do
    error = assert_raises(Ai::SchemaDefinition::DefinitionError) do
      Ai::SchemaDefinition.parse(
        {
          "name" => "unsafe",
          "schema" => {
            "type" => "object",
            "properties" => {},
            "$ref" => "Class.new"
          }
        }
      )
    end

    assert_includes error.message, "unsupported keys"
    assert_includes error.message, "$ref"
  end

  test "requires array item schemas and known required properties" do
    error = assert_raises(Ai::SchemaDefinition::DefinitionError) do
      Ai::SchemaDefinition.parse(
        {
          "name" => "invalid",
          "schema" => {
            "type" => "object",
            "properties" => { "items" => { "type" => "array" } },
            "required" => [ "missing" ]
          }
        }
      )
    end

    assert_includes error.message, "required must contain only property names"
    assert_includes error.message, "items must be an object"
  end
end
