require "test_helper"

class Ai::TransientDatabaseErrorTest < ActiveSupport::TestCase
  test "matches transient errors directly and through the cause chain" do
    assert Ai::TransientDatabaseError.match?(ActiveRecord::ConnectionNotEstablished.new("gone"))

    wrapped = begin
      begin
        raise ActiveRecord::Deadlocked, "deadlock"
      rescue ActiveRecord::Deadlocked
        raise RuntimeError, "wrapper"
      end
    rescue RuntimeError => error
      error
    end
    assert Ai::TransientDatabaseError.match?(wrapped)
  end

  test "does not match ordinary errors" do
    assert_not Ai::TransientDatabaseError.match?(ArgumentError.new("bad"))
    assert_not Ai::TransientDatabaseError.match?(nil)
  end
end
