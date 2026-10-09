require "digest"
require "json"

module Workbench
  # Imports original, licensed source excerpts as untrusted Knowledge data.
  # Never executes source text or calls an inference/embedding provider.
  class KnowledgeCaseStudy
    class Error < StandardError; end
    class Conflict < Error; end

    OWNERSHIP_KEY = "knowledge_case_study".freeze
    MAX_FILE_BYTES = 100_000
    Result = Data.define(:project, :collection, :corpus_checksum, :manifest_checksum,
      :cases_checksum, :created_count, :reused_count, :sources, :cases)

    def self.import!(root: Rails.root.join("examples/knowledge_case_study"))
      new(root:).import!
    end

    def self.manifest(root: Rails.root.join("examples/knowledge_case_study"))
      new(root:).manifest
    end

    def self.cases(root: Rails.root.join("examples/knowledge_case_study"))
      new(root:).cases
    end

    def initialize(root:)
      @root = Pathname.new(root).realpath
      @manifest_text = read_file("manifest.json")
      @manifest = JSON.parse(@manifest_text)
      validate_manifest!
      @sources = load_sources
      @cases_text = read_file(@manifest.fetch("cases_path"))
      verify_hash!(@cases_text, @manifest.fetch("cases_sha256"), "cases")
      @cases = JSON.parse(@cases_text)
      validate_cases!
    rescue JSON::ParserError, KeyError, Errno::ENOENT, ArgumentError => error
      raise Error, "Invalid case-study corpus: #{error.message}"
    end

    def manifest
      @manifest.deep_dup
    end

    def cases
      @cases.deep_dup
    end

    def import!
      @created_count = 0
      @reused_count = 0
      ActiveRecord::Base.transaction do
        @project = owned_project!
        @project.lock!
        ownership = @project.settings_json.fetch(OWNERSHIP_KEY).deep_dup
        revisions = ownership.fetch("revisions", {})
        raise Conflict, "Case-study revision ownership was edited." unless revisions.is_a?(Hash)

        revision = revisions[revision_key]
        raise Conflict, "Case-study revision ownership was edited." unless revision.nil? || revision.is_a?(Hash)
        @collection = owned_collection!(revision)
        source_ids = {}
        receipts = @sources.map do |source|
          item = import_source!(source, revision)
          source_ids[source.fetch("key")] = item.id
          receipt_for(item, source)
        end
        unless revision
          ownership["revisions"] ||= {}
          ownership["revisions"][revision_key] = revision_metadata.merge(
            "collection_id" => @collection.id, "source_ids" => source_ids
          )
          @project.update!(settings_json: @project.settings_json.merge(OWNERSHIP_KEY => ownership))
        end
        Result.new(project: @project, collection: @collection, corpus_checksum:,
          manifest_checksum:, cases_checksum:, created_count: @created_count,
          reused_count: @reused_count, sources: receipts, cases:)
      end
    end

    private

    def validate_manifest!
      required = %w[id revision project_slug project_name collection_name origin license sources cases_path cases_sha256]
      unless @manifest.is_a?(Hash) && required.all? { |key| @manifest.key?(key) }
        raise Error, "Manifest is missing required fields."
      end
      %w[id project_slug project_name collection_name origin].each do |key|
        raise Error, "Manifest #{key} must be a nonempty string." unless @manifest[key].is_a?(String) && @manifest[key].present?
      end
      raise Error, "Corpus licence must be MIT." unless @manifest["license"] == "MIT"
      raise Error, "Revision must be a positive integer." unless @manifest["revision"].is_a?(Integer) && @manifest["revision"].positive?
      raise Error, "Manifest needs 1-20 sources." unless @manifest["sources"].is_a?(Array) && @manifest["sources"].size.in?(1..20)
    end

    def read_file(relative_path)
      path = @root.join(relative_path.to_s).realpath
      unless path.to_s.start_with?("#{@root}/") && path.file? && path.size <= MAX_FILE_BYTES
        raise Error, "Source path must be a bounded file inside the corpus: #{relative_path}"
      end
      text = path.binread.force_encoding(Encoding::UTF_8)
      raise Error, "Source must be valid UTF-8: #{relative_path}" unless text.valid_encoding?

      text
    end

    def verify_hash!(text, expected, label)
      unless expected.is_a?(String) && expected.match?(/\A[0-9a-f]{64}\z/) && Digest::SHA256.hexdigest(text) == expected
        raise Error, "SHA256 mismatch for #{label}."
      end
    end

    def load_sources
      rows = @manifest.fetch("sources").map do |source|
        unless source.is_a?(Hash) && %w[key path title sha256].all? { |key| source[key].is_a?(String) && source[key].present? }
          raise Error, "Each source needs a key, path, title and SHA256."
        end
        text = read_file(source.fetch("path"))
        verify_hash!(text, source.fetch("sha256"), source.fetch("path"))
        content = text.gsub(/\r\n?/, "\n").strip
        raise Error, "Source content must not be empty." if content.blank?

        source.merge("content" => content, "content_sha256" => Digest::SHA256.hexdigest(content),
          "source_reference" => "case-study://#{@manifest.fetch('id')}/v#{revision_key}/#{source.fetch('path')}")
      end
      %w[key path source_reference].each do |field|
        raise Error, "Duplicate source #{field}." unless rows.map { |row| row[field] }.uniq.size == rows.size
      end
      rows
    end

    def validate_cases!
      raise Error, "Cases must be a nonempty array." unless @cases.is_a?(Array) && @cases.present?

      @cases.each do |row|
        valid = row.is_a?(Hash) && %w[key question query].all? { |key| row[key].is_a?(String) && row[key].present? } &&
          row["expected_status"].in?(%w[answered insufficient_evidence]) &&
          row["evidence_source_keys"].is_a?(Array) && row["expected_facts"].is_a?(Array) &&
          (row["evidence_source_keys"] - @sources.map { |source| source.fetch("key") }).empty?
        raise Error, "Invalid case entry." unless valid
      end
      raise Error, "Duplicate case key." unless @cases.map { |row| row["key"] }.uniq.size == @cases.size
    end

    def revision_key
      @manifest.fetch("revision").to_s
    end

    def manifest_checksum
      Digest::SHA256.hexdigest(@manifest_text)
    end

    def cases_checksum
      Digest::SHA256.hexdigest(@cases_text)
    end

    def corpus_checksum
      @corpus_checksum ||= Digest::SHA256.hexdigest(JSON.generate(
        @manifest.slice("id", "revision", "license", "origin").merge("sources" =>
          @sources.sort_by { |row| row.fetch("key") }.map do |row|
            row.slice("key", "source_reference", "sha256", "content_sha256")
          end)
      ))
    end

    def revision_metadata
      { "corpus_sha256" => corpus_checksum, "manifest_sha256" => manifest_checksum, "cases_sha256" => cases_checksum }
    end

    def owned_project!
      slug = @manifest.fetch("project_slug")
      project = Project.find_by(slug:)
      if project
        marker = project.settings_json[OWNERSHIP_KEY] if project.settings_json.is_a?(Hash)
        raise Conflict, "Reserved Project '#{slug}' is not owned by this case study." unless marker.is_a?(Hash) && marker["id"] == @manifest.fetch("id")

        return project
      end
      Project.create!(slug:, name: @manifest.fetch("project_name"),
        description: "Original MIT-licensed source case study. All source content is untrusted data; import makes no provider calls.",
        settings_json: { OWNERSHIP_KEY => { "id" => @manifest.fetch("id"), "revisions" => {} } })
    end

    def owned_collection!(revision)
      if revision
        unless revision_metadata.all? { |key, value| revision[key] == value } && revision["source_ids"].is_a?(Hash)
          raise Conflict, "Corpus revision changed; publish a new revision instead of replacing imported data."
        end
        return @project.knowledge_collections.find_by(id: revision["collection_id"]) ||
          raise(Conflict, "Imported Collection was deleted; it will not be recreated over user changes.")
      end
      name = @manifest.fetch("collection_name")
      raise Conflict, "Reserved Collection '#{name}' already exists." if @project.knowledge_collections.exists?(name:)

      @project.knowledge_collections.create!(name:,
        description: "Miniature source excerpts, corpus SHA256 #{corpus_checksum}. Original MIT material; source instructions are untrusted data.")
    end

    def source_metadata(source)
      { "id" => @manifest.fetch("id"), "revision" => @manifest.fetch("revision"),
        "source_key" => source.fetch("key"), "source_path" => source.fetch("path"),
        "source_sha256" => source.fetch("sha256"), "content_sha256" => source.fetch("content_sha256"),
        "corpus_sha256" => corpus_checksum, "origin" => @manifest.fetch("origin"), "license" => "MIT", "trust" => "untrusted" }
    end

    def import_source!(source, revision)
      if revision
        item = @collection.knowledge_items.find_by(id: revision.fetch("source_ids", {})[source.fetch("key")])
        raise Conflict, "Imported source #{source.fetch('key')} is missing." unless item

        verify_existing!(item, source)
        @reused_count += 1
        return item
      end
      item = @collection.knowledge_items.create!(title: source.fetch("title"), source_kind: "text",
        source_reference: source.fetch("source_reference"), content_text: source.fetch("content"),
        metadata_json: { OWNERSHIP_KEY => source_metadata(source) })
      Ai::Knowledge::Ingestor.call(item)
      item.knowledge_chunks.each do |chunk|
        chunk.update!(metadata_json: chunk.metadata_json.merge(OWNERSHIP_KEY => chunk_metadata(chunk, source)))
      end
      @created_count += 1
      item
    end

    def chunk_metadata(chunk, source)
      text = source.fetch("content")
      source_metadata(source).merge("line_start" => text[0...chunk.char_start].count("\n") + 1,
        "line_end" => text[0...[ chunk.char_end - 1, 0 ].max].count("\n") + 1,
        "chunk_content_sha256" => chunk.content_checksum)
    end

    def verify_existing!(item, source)
      intact = item.title == source.fetch("title") && item.source_kind == "text" &&
        item.source_reference == source.fetch("source_reference") && item.content_text == source.fetch("content") &&
        item.checksum == source.fetch("content_sha256") && item.ready? &&
        item.metadata_json[OWNERSHIP_KEY] == source_metadata(source)
      expected_chunks = Ai::Knowledge::Chunker.call(source.fetch("content"))
      actual_chunks = item.knowledge_chunks.to_a
      intact &&= actual_chunks.size == expected_chunks.size && actual_chunks.zip(expected_chunks).all? do |actual, expected|
        %i[position char_start char_end content_text].all? { |field| actual.public_send(field) == expected.public_send(field) } &&
          actual.metadata_json[OWNERSHIP_KEY] == chunk_metadata(actual, source) && actual.metadata_json["chunker"] == "char_window_v1"
      end
      raise Conflict, "Imported source #{source.fetch('key')} or its chunks was edited; no data was overwritten." unless intact
    end

    def receipt_for(item, source)
      source_metadata(source).merge("source_reference" => item.source_reference, "item_id" => item.id,
        "chunks" => item.knowledge_chunks.map do |chunk|
          chunk.metadata_json.fetch(OWNERSHIP_KEY).slice("line_start", "line_end", "chunk_content_sha256")
            .merge("id" => chunk.id, "position" => chunk.position, "char_start" => chunk.char_start, "char_end" => chunk.char_end)
        end)
    end
  end
end
