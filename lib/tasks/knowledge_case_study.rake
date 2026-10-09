namespace :workbench do
  namespace :knowledge_case_study do
    desc "Import the original MIT source case study without provider calls or overwriting edits"
    task import: :environment do
      result = Workbench::KnowledgeCaseStudy.import!
      puts JSON.pretty_generate(
        "project_id" => result.project.id, "project_slug" => result.project.slug,
        "collection_id" => result.collection.id,
        "collection_path" => Rails.application.routes.url_helpers.project_knowledge_collection_path(result.project, result.collection),
        "corpus_sha256" => result.corpus_checksum, "manifest_sha256" => result.manifest_checksum,
        "cases_sha256" => result.cases_checksum, "created_count" => result.created_count,
        "reused_count" => result.reused_count, "sources" => result.sources,
        "case_keys" => result.cases.map { |test_case| test_case.fetch("key") }, "provider_requests" => 0
      )
    rescue Workbench::KnowledgeCaseStudy::Error => error
      abort "Case-study import stopped: #{error.message}"
    end
  end
end
