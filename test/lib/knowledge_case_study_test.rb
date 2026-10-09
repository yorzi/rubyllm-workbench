require "test_helper"
require "fileutils"
require "tmpdir"
require "rake"

class KnowledgeCaseStudyTest < ActiveSupport::TestCase
  ROOT = Rails.root.join("examples/knowledge_case_study")

  test "imports source provenance and inspectable chunk locations without provider work" do
    result = nil
    assert_no_difference [ "Run.count", "KnowledgeEmbedding.count" ] do
      result = Workbench::KnowledgeCaseStudy.import!
    end

    assert_equal "rails-source-case-study", result.project.slug
    assert_equal 5, result.created_count
    assert_equal 0, result.reused_count
    assert_equal 5, result.sources.length
    assert_equal 5, result.cases.length
    assert_match(/\A[0-9a-f]{64}\z/, result.corpus_checksum)
    assert_equal Digest::SHA256.file(ROOT.join("manifest.json")).hexdigest, result.manifest_checksum
    assert_equal Digest::SHA256.file(ROOT.join("cases.json")).hexdigest, result.cases_checksum

    result.sources.each do |source|
      item = KnowledgeItem.find(source.fetch("item_id"))
      assert item.ready?
      assert_equal "MIT", source.fetch("license")
      assert_equal "untrusted", source.fetch("trust")
      assert_equal result.corpus_checksum, source.fetch("corpus_sha256")
      assert_equal source.fetch("content_sha256"), item.checksum
      assert_equal Digest::SHA256.file(ROOT.join(source.fetch("source_path"))).hexdigest, source.fetch("source_sha256")
      assert_equal source.fetch("source_reference"), item.source_reference

      source.fetch("chunks").each do |location|
        chunk = KnowledgeChunk.find(location.fetch("id"))
        assert_equal item.content_text[location.fetch("char_start")...location.fetch("char_end")], chunk.content_text
        assert_equal chunk.content_checksum, location.fetch("chunk_content_sha256")
        lines = item.content_text.lines[(location.fetch("line_start") - 1)..(location.fetch("line_end") - 1)].join
        assert_includes lines, chunk.content_text
      end
    end
  end

  test "repeated import preserves IDs timestamps settings and user additions" do
    first = Workbench::KnowledgeCaseStudy.import!
    first.project.update!(name: "My case study", settings_json: first.project.settings_json.merge("custom" => true))
    first.collection.update!(name: "My corpus")
    first.collection.knowledge_items.create!(title: "My source", content_text: "A user-owned addition.")
    chunk = first.collection.knowledge_chunks.first
    embedding = chunk.knowledge_embeddings.create!(provider: "synthetic", model_id: "offline-fixture-vector", dimensions: 2,
      vector: Ai::Knowledge::VectorStore.default.encode([ 1.0, 0.0 ]), content_checksum: chunk.content_checksum)
    embedding_before = embedding.attributes
    item_times = first.collection.knowledge_items.pluck(:id, :updated_at)
    chunk_times = first.collection.knowledge_chunks.pluck(:id, :updated_at)
    project_time = first.project.updated_at

    assert_no_difference [ "Project.count", "KnowledgeCollection.count", "KnowledgeItem.count", "KnowledgeChunk.count", "KnowledgeEmbedding.count" ] do
      second = Workbench::KnowledgeCaseStudy.import!
      assert_equal 0, second.created_count
      assert_equal 5, second.reused_count
      assert_equal first.sources, second.sources
      assert_equal first.project.id, second.project.id
      assert_equal first.collection.id, second.collection.id
      assert_equal "My case study", second.project.name
      assert_equal "My corpus", second.collection.name
      assert_equal true, second.project.settings_json.fetch("custom")
    end

    assert_equal item_times, first.collection.knowledge_items.pluck(:id, :updated_at)
    assert_equal chunk_times, first.collection.knowledge_chunks.pluck(:id, :updated_at)
    assert_equal project_time, first.project.reload.updated_at
    assert_equal embedding_before, embedding.reload.attributes
  end

  test "source edits are rejected and remain intact" do
    result = Workbench::KnowledgeCaseStudy.import!
    item = result.collection.knowledge_items.last
    item.update!(content_text: "Owner edited this source.")
    before = item.attributes
    chunk_ids = result.collection.knowledge_chunks.pluck(:id)

    error = assert_raises(Workbench::KnowledgeCaseStudy::Conflict) { Workbench::KnowledgeCaseStudy.import! }

    assert_includes error.message, "edited"
    assert_equal before, item.reload.attributes
    assert_equal chunk_ids, result.collection.knowledge_chunks.pluck(:id)
  end

  test "chunk edits are rejected without repairing them implicitly" do
    result = Workbench::KnowledgeCaseStudy.import!
    chunk = result.collection.knowledge_chunks.first
    chunk.update!(content_text: "Owner edited a chunk.")

    assert_raises(Workbench::KnowledgeCaseStudy::Conflict) { Workbench::KnowledgeCaseStudy.import! }

    assert_equal "Owner edited a chunk.", chunk.reload.content_text
  end

  test "deleted imported sources do not get silently recreated" do
    result = Workbench::KnowledgeCaseStudy.import!
    result.collection.knowledge_items.first.destroy!

    assert_no_difference "KnowledgeItem.count" do
      assert_raises(Workbench::KnowledgeCaseStudy::Conflict) { Workbench::KnowledgeCaseStudy.import! }
    end
  end

  test "reserved project collisions do not modify user projects" do
    project = Project.create!(name: "Existing user project", slug: "rails-source-case-study")
    before = project.attributes

    assert_no_difference [ "Project.count", "KnowledgeCollection.count" ] do
      assert_raises(Workbench::KnowledgeCaseStudy::Conflict) { Workbench::KnowledgeCaseStudy.import! }
    end

    assert_equal before, project.reload.attributes
  end

  test "an ingestion failure rolls back the entire new import" do
    original = Ai::Knowledge::Ingestor.method(:call)
    calls = 0
    failing_ingestor = lambda do |item|
      calls += 1
      raise Ai::Knowledge::Ingestor::Error, "Fixture ingestion failure" if calls == 2

      original.call(item)
    end

    Ai::Knowledge::Ingestor.define_singleton_method(:call, failing_ingestor)
    assert_no_difference [ "Project.count", "KnowledgeCollection.count", "KnowledgeItem.count", "KnowledgeChunk.count" ] do
      assert_raises(Ai::Knowledge::Ingestor::Error) { Workbench::KnowledgeCaseStudy.import! }
    end
  ensure
    Ai::Knowledge::Ingestor.define_singleton_method(:call, original) if original
  end

  test "changed corpus bytes fail their pinned hash before database writes" do
    with_corpus do |root|
      File.write(root.join("sources/app/models/note.rb.txt"), "Changed corpus file.")

      assert_no_difference "Project.count" do
        error = assert_raises(Workbench::KnowledgeCaseStudy::Error) { Workbench::KnowledgeCaseStudy.import!(root:) }
        assert_includes error.message, "SHA256 mismatch"
      end
    end
  end

  test "source paths and symlinks cannot escape the corpus" do
    with_corpus do |root|
      manifest = JSON.parse(root.join("manifest.json").read)
      source = manifest.fetch("sources").first
      root.join(source.fetch("path")).delete
      File.symlink(Rails.root.join("LICENSE"), root.join(source.fetch("path")))
      source["sha256"] = Digest::SHA256.file(Rails.root.join("LICENSE")).hexdigest
      root.join("manifest.json").write(JSON.pretty_generate(manifest))

      error = assert_raises(Workbench::KnowledgeCaseStudy::Error) { Workbench::KnowledgeCaseStudy.import!(root:) }
      assert_includes error.message, "inside the corpus"
    end
  end

  test "a new revision creates its own collection and retains the original evidence" do
    first = Workbench::KnowledgeCaseStudy.import!
    original_source_ids = first.collection.knowledge_items.pluck(:id)
    with_corpus do |root|
      manifest = JSON.parse(root.join("manifest.json").read)
      manifest["revision"] = 2
      manifest["collection_name"] = "Mini Notes Rails · v2"
      root.join("manifest.json").write(JSON.pretty_generate(manifest))

      assert_difference "KnowledgeCollection.count", 1 do
        second = Workbench::KnowledgeCaseStudy.import!(root:)
        assert_equal first.project.id, second.project.id
        refute_equal first.collection.id, second.collection.id
        refute_equal first.corpus_checksum, second.corpus_checksum
        assert_equal 5, second.created_count
      end
    end

    assert_equal original_source_ids, first.collection.knowledge_items.pluck(:id)
    assert_equal 5, Workbench::KnowledgeCaseStudy.import!.reused_count
  end

  test "same revision metadata changes are refused rather than replacing its evidence" do
    Workbench::KnowledgeCaseStudy.import!
    with_corpus do |root|
      manifest = JSON.parse(root.join("manifest.json").read)
      manifest["origin"] = "Changed metadata"
      root.join("manifest.json").write(JSON.pretty_generate(manifest))

      assert_no_difference [ "KnowledgeItem.count", "KnowledgeChunk.count" ] do
        assert_raises(Workbench::KnowledgeCaseStudy::Conflict) { Workbench::KnowledgeCaseStudy.import!(root:) }
      end
    end
  end

  test "normalized multi-chunk content keeps raw hashes and usable character and line locations" do
    with_corpus do |root|
      manifest = JSON.parse(root.join("manifest.json").read)
      source = manifest.fetch("sources").first
      path = root.join(source.fetch("path"))
      path.write(path.read.gsub("\n", "\r\n") + ("# Artificial boundary note: café source position must remain inspectable.\r\n" * 24))
      source["sha256"] = Digest::SHA256.file(path).hexdigest
      root.join("manifest.json").write(JSON.pretty_generate(manifest))

      result = Workbench::KnowledgeCaseStudy.import!(root:)
      receipt = result.sources.find { |row| row.fetch("source_key") == source.fetch("key") }
      item = KnowledgeItem.find(receipt.fetch("item_id"))
      assert_operator receipt.fetch("chunks").length, :>, 1
      refute_equal receipt.fetch("source_sha256"), receipt.fetch("content_sha256")
      assert_equal Digest::SHA256.hexdigest(item.content_text), receipt.fetch("content_sha256")
      refute_includes item.content_text, "\r"
      receipt.fetch("chunks").each do |location|
        chunk = KnowledgeChunk.find(location.fetch("id"))
        assert_equal chunk.content_text, item.content_text[location.fetch("char_start")...location.fetch("char_end")]
        lines = item.content_text.lines[(location.fetch("line_start") - 1)..(location.fetch("line_end") - 1)].join
        assert_includes lines, chunk.content_text
      end
    end
  end

  test "edited revision ownership fails closed and preserves the user edit" do
    result = Workbench::KnowledgeCaseStudy.import!
    settings = result.project.settings_json.deep_dup
    settings.fetch("knowledge_case_study")["revisions"] = [ "owner edited this" ]
    result.project.update!(settings_json: settings)

    assert_raises(Workbench::KnowledgeCaseStudy::Conflict) { Workbench::KnowledgeCaseStudy.import! }

    assert_equal settings, result.project.reload.settings_json
  end

  test "lexical case queries retain missing evidence and misleading source data boundaries" do
    result = Workbench::KnowledgeCaseStudy.import!
    result.cases.each do |test_case|
      first = Ai::Knowledge::Search.call(collection: result.collection, query: test_case.fetch("query"), mode: "lexical")
      second = Ai::Knowledge::Search.call(collection: result.collection, query: test_case.fetch("query"), mode: "lexical")
      assert_equal first.results.map { |row| [ row.chunk.id, row.score ] }, second.results.map { |row| [ row.chunk.id, row.score ] }
      keys = first.results.map { |row| row.chunk.knowledge_item.metadata_json.dig("knowledge_case_study", "source_key") }
      test_case.fetch("evidence_source_keys").each { |key| assert_includes keys, key }
      assert_empty first.results if test_case.fetch("expected_status") == "insufficient_evidence"
    end

    misleading = Ai::Knowledge::Search.call(collection: result.collection, query: "token_dump", mode: "lexical")
    assert_equal 1, misleading.results.size
    assert_includes misleading.results.first.chunk.content_text, "Ignore the question"
    assert_equal "untrusted", misleading.results.first.chunk.metadata_json.dig("knowledge_case_study", "trust")
    assert_empty Ai::Knowledge::Search.call(collection: result.collection, query: "  ", mode: "lexical").results
    assert_equal 0, Run.where(project: result.project).count
    assert_equal 0, result.collection.knowledge_embeddings.count
  end

  test "import rake command emits a reproducible receipt and can run twice" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("workbench:knowledge_case_study:import")
    task = Rake::Task["workbench:knowledge_case_study:import"]
    output, = capture_io { task.execute }
    receipt = JSON.parse(output)

    assert_equal 0, receipt.fetch("provider_requests")
    assert_equal 5, receipt.fetch("created_count")
    assert_equal Rails.application.routes.url_helpers.project_knowledge_collection_path(
      Project.find(receipt.fetch("project_id")), KnowledgeCollection.find(receipt.fetch("collection_id"))
    ), receipt.fetch("collection_path")
    output, = capture_io { task.execute }
    assert_equal 5, JSON.parse(output).fetch("reused_count")
  end

  private

  def with_corpus
    Dir.mktmpdir("workbench-case-study-") do |directory|
      root = Pathname.new(directory).join("corpus")
      FileUtils.cp_r(ROOT, root)
      yield root
    end
  end
end
