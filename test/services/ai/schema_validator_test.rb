require "test_helper"

class Ai::SchemaValidatorTest < ActiveSupport::TestCase
  setup do
    @definition = Ai::SchemaDefinition.parse(
      {
        "name" => "ticket",
        "schema" => {
          "type" => "object",
          "properties" => {
            "title" => { "type" => "string" },
            "priority" => { "type" => "integer", "enum" => [ 1, 2, 3 ] },
            "resolved" => { "type" => "boolean" }
          },
          "required" => %w[title priority resolved],
          "additionalProperties" => false
        }
      }
    )
  end

  test "accepts a value that matches the constrained schema" do
    assert_empty Ai::SchemaValidator.new(@definition).errors_for(
      { "title" => "Broken link", "priority" => 2, "resolved" => false }
    )
  end

  test "reports missing, wrong-type, enum, and unknown fields" do
    errors = Ai::SchemaValidator.new(@definition).errors_for(
      { "title" => 12, "priority" => 4, "extra" => true }
    )

    assert_includes errors, "$.title must be a string"
    assert_includes errors, "$.priority must be one of 1, 2, 3"
    assert_includes errors, "$.resolved is required"
    assert_includes errors, "$.extra is not allowed"
  end
end
