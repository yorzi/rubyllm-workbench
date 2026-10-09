require "test_helper"
require "tmpdir"
require "open3"
require_relative "../support/read_only_demo_helpers"

class DemoModeTest < ActiveSupport::TestCase
  include ReadOnlyDemoHelpers

  test "boot rejects missing, substituted and schema-stale snapshots" do
    Dir.mktmpdir("workbench-demo-integrity") do |directory|
      database = Pathname.new(directory).join("snapshot.sqlite3")
      manifest = Pathname.new(directory).join("snapshot.json")
      with_demo_mode do
        with_replaced_method(Workbench::DemoMode, :snapshot_path, -> { database }) do
          with_replaced_method(Workbench::DemoMode, :manifest_path, -> { manifest }) do
            error = assert_raises(ArgumentError) { Workbench::DemoMode.verify_boot! }
            assert_match(/missing/, error.message)
            manifest.write("[]")
            assert_raises(ArgumentError) { Workbench::DemoMode.verify_boot! }
            database.write("synthetic database fixture")
            content = { "format" => 1, "synthetic" => true,
              "schema_sha256" => Digest::SHA256.file(Rails.root.join("db/schema.rb")).hexdigest,
              "database_sha256" => Digest::SHA256.file(database).hexdigest }
            manifest.write(JSON.generate(content))
            assert_nothing_raised { Workbench::DemoMode.verify_boot! }

            database.write("substituted database")
            assert_raises(ArgumentError) { Workbench::DemoMode.verify_boot! }
            content["database_sha256"] = Digest::SHA256.file(database).hexdigest
            content["schema_sha256"] = "old schema"
            manifest.write(JSON.generate(content))
            assert_raises(ArgumentError) { Workbench::DemoMode.verify_boot! }
          end
        end
      end
    end
  end

  test "container server entrypoint skips maintenance only in demo mode" do
    Dir.mktmpdir("workbench-demo-entrypoint") do |directory|
      FileUtils.mkdir_p(File.join(directory, "bin"))
      rails = File.join(directory, "bin/rails")
      File.write(rails, "#!/bin/sh\nprintf '%s\\n' \"$*\"\n")
      File.chmod(0o755, rails)
      [ [ "1", "server\n" ], [ "0", "db:prepare\nserver\n" ] ].each do |mode, expected|
        output, status = Open3.capture2e({ "WORKBENCH_DEMO" => mode }, "bash",
          Rails.root.join("bin/docker-entrypoint").to_s, "./bin/rails", "server", chdir: directory)
        assert status.success?, output
        assert_equal expected, output
      end
    end
  end
end
