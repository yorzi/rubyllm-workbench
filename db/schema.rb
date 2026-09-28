# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_21_183000) do
# Could not dump table "_sqliteai_vector" because of following StandardError
#   Unknown type 'ANY' for column 'value'


  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "agent_definitions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "instructions", null: false
    t.string "model_id", null: false
    t.string "name", null: false
    t.json "options_json", default: {}, null: false
    t.integer "project_id", null: false
    t.string "provider", null: false
    t.json "provider_tools_json", default: [], null: false
    t.integer "revision", default: 1, null: false
    t.json "tool_keys_json", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "name"], name: "index_agent_definitions_on_project_id_and_name", unique: true
    t.index ["project_id", "updated_at"], name: "index_agent_definitions_on_project_id_and_updated_at"
    t.index ["project_id"], name: "index_agent_definitions_on_project_id"
  end

  create_table "agent_run_deliveries", force: :cascade do |t|
    t.integer "approval_invocation_id"
    t.datetime "available_at", null: false
    t.string "claim_token"
    t.datetime "claimed_until"
    t.datetime "created_at", null: false
    t.string "dedupe_key", null: false
    t.datetime "delivered_at"
    t.integer "dispatch_attempts", default: 0, null: false
    t.integer "expected_generation"
    t.string "intent", null: false
    t.string "last_error_class"
    t.integer "run_id", null: false
    t.datetime "updated_at", null: false
    t.index ["approval_invocation_id"], name: "index_agent_run_deliveries_on_approval_invocation_id"
    t.index ["dedupe_key"], name: "index_agent_run_deliveries_on_dedupe_key", unique: true
    t.index ["delivered_at", "available_at", "claimed_until"], name: "index_agent_run_deliveries_for_dispatch"
    t.index ["run_id"], name: "index_agent_run_deliveries_on_run_id"
  end

  create_table "approvals", force: :cascade do |t|
    t.string "actor", default: "local_user", null: false
    t.datetime "created_at", null: false
    t.datetime "decided_at"
    t.text "decision_note"
    t.datetime "requested_at", null: false
    t.string "status", default: "pending", null: false
    t.integer "tool_invocation_id", null: false
    t.datetime "updated_at", null: false
    t.index ["status", "requested_at"], name: "index_approvals_on_status_and_requested_at"
    t.index ["tool_invocation_id"], name: "index_approvals_on_invocation_unique", unique: true
  end

  create_table "artifacts", force: :cascade do |t|
    t.integer "attempt_id"
    t.json "content_json"
    t.text "content_text"
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.integer "knowledge_item_id"
    t.json "metadata_json", default: {}, null: false
    t.string "name"
    t.integer "run_id"
    t.string "source_tool_call_id"
    t.datetime "updated_at", null: false
    t.index ["attempt_id"], name: "index_artifacts_on_attempt_id"
    t.index ["knowledge_item_id"], name: "index_artifacts_on_knowledge_item_id"
    t.index ["run_id", "kind"], name: "index_artifacts_on_run_id_and_kind"
    t.index ["run_id", "source_tool_call_id"], name: "index_artifacts_on_run_and_source_tool_call", unique: true
    t.index ["run_id"], name: "index_artifacts_on_run_id"
  end

  create_table "attempts", force: :cascade do |t|
    t.integer "cache_read_tokens"
    t.integer "cache_write_tokens"
    t.string "cost_status"
    t.datetime "created_at", null: false
    t.string "currency"
    t.integer "duration_ms"
    t.string "error_class"
    t.string "error_code"
    t.text "error_message"
    t.decimal "estimated_cost"
    t.string "finish_reason"
    t.datetime "finished_at"
    t.integer "input_tokens"
    t.json "metadata_json"
    t.string "model_id"
    t.integer "output_tokens"
    t.string "provider"
    t.decimal "reported_cost"
    t.string "request_id"
    t.json "ruby_llm_usage_ids_json"
    t.integer "run_id", null: false
    t.integer "sequence"
    t.datetime "started_at"
    t.string "status"
    t.integer "thinking_tokens"
    t.integer "time_to_first_output_ms"
    t.datetime "updated_at", null: false
    t.index ["run_id"], name: "index_attempts_on_run_id"
  end

  create_table "chats", force: :cascade do |t|
    t.boolean "cancelled", default: false, null: false
    t.datetime "created_at", null: false
    t.integer "project_id", null: false
    t.bigint "ruby_llm_model_id", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["project_id", "created_at"], name: "index_chats_on_project_id_and_created_at"
    t.index ["project_id"], name: "index_chats_on_project_id"
    t.index ["ruby_llm_model_id"], name: "index_chats_on_ruby_llm_model_id"
  end

  create_table "evaluation_case_judgments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_summary"
    t.integer "evaluation_case_result_id", null: false
    t.datetime "finished_at"
    t.json "input_snapshot_json", null: false
    t.json "result_json"
    t.integer "run_id", null: false
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.datetime "updated_at", null: false
    t.index ["evaluation_case_result_id"], name: "index_evaluation_case_judgments_on_case_result", unique: true
    t.index ["run_id"], name: "index_evaluation_case_judgments_on_run_id", unique: true
    t.index ["status", "started_at"], name: "index_evaluation_case_judgments_for_recovery"
  end

  create_table "evaluation_case_results", force: :cascade do |t|
    t.json "actual_output_json"
    t.string "case_key", null: false
    t.integer "case_position", null: false
    t.datetime "created_at", null: false
    t.text "error_summary"
    t.integer "evaluation_dataset_revision_id", null: false
    t.integer "evaluation_execution_id", null: false
    t.json "expected_output_json", null: false
    t.datetime "finished_at"
    t.json "input_json", null: false
    t.boolean "passed"
    t.json "rubric_json", default: [], null: false
    t.integer "run_id"
    t.string "schema_status"
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.datetime "submission_unknown_at"
    t.string "transport_status"
    t.datetime "updated_at", null: false
    t.index ["evaluation_dataset_revision_id"], name: "idx_on_evaluation_dataset_revision_id_3e65cf63d6"
    t.index ["evaluation_execution_id", "case_key"], name: "index_evaluation_case_results_unique_case", unique: true
    t.index ["evaluation_execution_id"], name: "index_evaluation_case_results_on_evaluation_execution_id"
    t.index ["run_id"], name: "index_evaluation_case_results_on_run_id", unique: true
  end

  create_table "evaluation_case_reviews", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "evaluation_case_result_id", null: false
    t.text "rationale"
    t.string "reviewer_label", null: false
    t.json "rubric_ratings_json", default: {}, null: false
    t.datetime "updated_at", null: false
    t.string "verdict", null: false
    t.index ["evaluation_case_result_id"], name: "index_evaluation_case_reviews_on_case_result"
  end

  create_table "evaluation_comparisons", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "dataset_snapshot_json", null: false
    t.integer "evaluation_dataset_revision_id", null: false
    t.integer "experiment_id"
    t.json "experiment_snapshot_json", null: false
    t.json "model_targets_json", null: false
    t.integer "project_id", null: false
    t.string "requested_by", null: false
    t.datetime "updated_at", null: false
    t.index ["evaluation_dataset_revision_id"], name: "index_evaluation_comparisons_on_evaluation_dataset_revision_id"
    t.index ["experiment_id"], name: "index_evaluation_comparisons_on_experiment_id"
    t.index ["project_id", "created_at"], name: "index_evaluation_comparisons_on_project_and_created"
    t.index ["project_id"], name: "index_evaluation_comparisons_on_project_id"
  end

  create_table "evaluation_dataset_case_attachments", force: :cascade do |t|
    t.string "case_key", null: false
    t.datetime "created_at", null: false
    t.integer "evaluation_dataset_revision_id", null: false
    t.integer "position", null: false
    t.datetime "updated_at", null: false
    t.index ["evaluation_dataset_revision_id", "case_key", "position"], name: "index_evaluation_case_attachments_on_revision_case_position", unique: true
    t.index ["evaluation_dataset_revision_id"], name: "idx_on_evaluation_dataset_revision_id_bcfb68356f"
  end

  create_table "evaluation_dataset_revisions", force: :cascade do |t|
    t.json "cases_json", null: false
    t.datetime "created_at", null: false
    t.integer "evaluation_dataset_id", null: false
    t.integer "revision", null: false
    t.datetime "updated_at", null: false
    t.index ["evaluation_dataset_id", "revision"], name: "index_evaluation_dataset_revisions_unique_version", unique: true
    t.index ["evaluation_dataset_id"], name: "index_evaluation_dataset_revisions_on_evaluation_dataset_id"
  end

  create_table "evaluation_datasets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "current_revision", default: 0, null: false
    t.text "description"
    t.string "name", null: false
    t.integer "project_id", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "name"], name: "index_evaluation_datasets_on_project_id_and_name", unique: true
    t.index ["project_id", "updated_at"], name: "index_evaluation_datasets_on_project_id_and_updated_at"
    t.index ["project_id"], name: "index_evaluation_datasets_on_project_id"
  end

  create_table "evaluation_executions", force: :cascade do |t|
    t.integer "case_count", null: false
    t.datetime "created_at", null: false
    t.integer "evaluation_comparison_id"
    t.integer "evaluation_dataset_revision_id", null: false
    t.string "execution_mode", default: "individual", null: false
    t.integer "experiment_id"
    t.datetime "finished_at"
    t.json "input_snapshot_json", null: false
    t.string "model_id", null: false
    t.integer "project_id", null: false
    t.string "provider", null: false
    t.text "provider_batch_error"
    t.string "provider_batch_id"
    t.string "provider_batch_raw_status"
    t.datetime "provider_batch_refresh_started_at"
    t.datetime "provider_batch_refreshed_at"
    t.string "provider_batch_status"
    t.datetime "provider_batch_submitted_at"
    t.string "requested_by", null: false
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.datetime "updated_at", null: false
    t.index ["evaluation_comparison_id", "provider", "model_id"], name: "index_evaluation_executions_on_comparison_and_model", unique: true, where: "evaluation_comparison_id IS NOT NULL"
    t.index ["evaluation_comparison_id"], name: "index_evaluation_executions_on_evaluation_comparison_id"
    t.index ["evaluation_dataset_revision_id", "created_at"], name: "index_evaluation_executions_on_dataset_revision_and_created"
    t.index ["evaluation_dataset_revision_id"], name: "index_evaluation_executions_on_evaluation_dataset_revision_id"
    t.index ["experiment_id"], name: "index_evaluation_executions_on_experiment_id"
    t.index ["project_id", "created_at"], name: "index_evaluation_executions_on_project_id_and_created_at"
    t.index ["project_id"], name: "index_evaluation_executions_on_project_id"
    t.index ["provider", "provider_batch_id"], name: "index_evaluation_executions_on_provider_batch", unique: true, where: "provider_batch_id IS NOT NULL"
  end

  create_table "experiment_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_summary"
    t.integer "experiment_id", null: false
    t.datetime "finished_at"
    t.json "input_snapshot_json", null: false
    t.integer "project_id", null: false
    t.string "requested_by", null: false
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.integer "target_count", null: false
    t.datetime "updated_at", null: false
    t.index ["experiment_id", "created_at"], name: "index_experiment_executions_on_experiment_id_and_created_at"
    t.index ["experiment_id"], name: "index_experiment_executions_on_experiment_id"
    t.index ["project_id", "created_at"], name: "index_experiment_executions_on_project_id_and_created_at"
    t.index ["project_id"], name: "index_experiment_executions_on_project_id"
  end

  create_table "experiments", force: :cascade do |t|
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.text "description"
    t.json "generation_options_json", default: {}, null: false
    t.text "input_prompt", null: false
    t.string "name", null: false
    t.integer "project_id", null: false
    t.integer "revision", default: 1, null: false
    t.json "schema_json", null: false
    t.string "status", default: "runnable", null: false
    t.text "system_prompt"
    t.datetime "updated_at", null: false
    t.index ["project_id", "status", "updated_at"], name: "index_experiments_on_project_id_and_status_and_updated_at"
    t.index ["project_id"], name: "index_experiments_on_project_id"
  end

  create_table "knowledge_chunks", force: :cascade do |t|
    t.integer "char_end", null: false
    t.integer "char_start", null: false
    t.text "content_text", null: false
    t.datetime "created_at", null: false
    t.integer "knowledge_item_id", null: false
    t.json "metadata_json", default: {}, null: false
    t.integer "position", null: false
    t.datetime "updated_at", null: false
    t.index ["knowledge_item_id", "position"], name: "index_knowledge_chunks_on_knowledge_item_id_and_position", unique: true
    t.index ["knowledge_item_id"], name: "index_knowledge_chunks_on_knowledge_item_id"
  end

  create_table "knowledge_collections", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "embedded_at"
    t.integer "embedding_dimensions"
    t.text "embedding_error"
    t.string "embedding_model_id"
    t.string "embedding_provider"
    t.string "embedding_status", default: "none", null: false
    t.string "name", null: false
    t.integer "project_id", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "name"], name: "index_knowledge_collections_on_project_id_and_name"
    t.index ["project_id"], name: "index_knowledge_collections_on_project_id"
  end

  create_table "knowledge_embeddings", force: :cascade do |t|
    t.string "content_checksum", null: false
    t.datetime "created_at", null: false
    t.integer "dimensions", null: false
    t.integer "input_tokens"
    t.integer "knowledge_chunk_id", null: false
    t.json "metadata_json", default: {}, null: false
    t.string "model_id", null: false
    t.string "provider", null: false
    t.decimal "reported_cost", precision: 16, scale: 10
    t.string "status", default: "ready", null: false
    t.datetime "updated_at", null: false
    t.binary "vector", null: false
    t.index ["knowledge_chunk_id", "model_id"], name: "index_knowledge_embeddings_on_chunk_and_model", unique: true
    t.index ["knowledge_chunk_id"], name: "index_knowledge_embeddings_on_knowledge_chunk_id"
    t.index ["model_id", "status"], name: "index_knowledge_embeddings_on_model_and_status"
  end

  create_table "knowledge_items", force: :cascade do |t|
    t.string "checksum", null: false
    t.text "content_text", null: false
    t.datetime "created_at", null: false
    t.text "error_summary"
    t.datetime "extracted_at"
    t.text "extraction_error"
    t.json "extraction_metadata_json", default: {}, null: false
    t.string "extraction_status", default: "not_required", null: false
    t.string "extractor"
    t.string "ingestion_status", default: "pending", null: false
    t.integer "knowledge_collection_id", null: false
    t.json "metadata_json", default: {}, null: false
    t.string "source_kind", default: "text", null: false
    t.string "source_reference"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["extraction_status"], name: "index_knowledge_items_on_extraction_status"
    t.index ["knowledge_collection_id", "checksum"], name: "index_knowledge_items_on_knowledge_collection_id_and_checksum"
    t.index ["knowledge_collection_id", "ingestion_status"], name: "idx_on_knowledge_collection_id_ingestion_status_6361f5fa8c"
    t.index ["knowledge_collection_id"], name: "index_knowledge_items_on_knowledge_collection_id"
  end

  create_table "knowledge_vector_index_1024", primary_key: "knowledge_embedding_id", id: :integer, default: nil, force: :cascade do |t|
    t.integer "knowledge_collection_id", null: false
    t.text "model_id", null: false
    t.binary "vector", null: false
  end

  create_table "lifecycle_events", force: :cascade do |t|
    t.integer "approval_id"
    t.integer "artifact_id"
    t.integer "attempt_id"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.string "event_key", null: false
    t.string "name", null: false
    t.datetime "occurred_at", null: false
    t.json "payload_json", default: {}, null: false
    t.integer "run_id", null: false
    t.string "source", default: "application", null: false
    t.integer "tool_invocation_id"
    t.datetime "updated_at", null: false
    t.index ["approval_id"], name: "index_lifecycle_events_on_approval_id"
    t.index ["artifact_id"], name: "index_lifecycle_events_on_artifact_id"
    t.index ["attempt_id"], name: "index_lifecycle_events_on_attempt_id"
    t.index ["event_key"], name: "index_lifecycle_events_on_event_key", unique: true
    t.index ["name", "occurred_at"], name: "index_lifecycle_events_on_name_and_occurred_at"
    t.index ["run_id", "occurred_at", "id"], name: "index_lifecycle_events_on_run_and_occurred_at"
    t.index ["run_id"], name: "index_lifecycle_events_on_run_id"
    t.index ["tool_invocation_id"], name: "index_lifecycle_events_on_tool_invocation_id"
  end

  create_table "messages", force: :cascade do |t|
    t.boolean "cache_until_here", default: false, null: false
    t.bigint "chat_id", null: false
    t.json "citations"
    t.text "content"
    t.datetime "created_at", null: false
    t.string "finish_reason"
    t.json "raw_content"
    t.json "raw_reasoning"
    t.string "role", null: false
    t.json "server_tool_calls"
    t.text "thinking_signature"
    t.text "thinking_text"
    t.datetime "updated_at", null: false
    t.index ["chat_id"], name: "index_messages_on_chat_id"
  end

  create_table "projects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name"
    t.json "settings_json"
    t.string "slug"
    t.datetime "updated_at", null: false
  end

  create_table "ruby_llm_batches", force: :cascade do |t|
    t.string "batch_protocol"
    t.json "chat_ids", default: []
    t.string "chat_type"
    t.boolean "completed", default: false, null: false
    t.datetime "created_at", null: false
    t.string "provider", null: false
    t.string "provider_batch_id", null: false
    t.string "raw_status"
    t.json "reported_cost"
    t.json "request_counts"
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "provider_batch_id"], name: "index_ruby_llm_batches_on_provider_and_provider_batch_id", unique: true
    t.index ["status"], name: "index_ruby_llm_batches_on_status"
  end

  create_table "ruby_llm_models", force: :cascade do |t|
    t.json "capabilities", default: []
    t.integer "context_window"
    t.datetime "created_at", null: false
    t.string "family"
    t.date "knowledge_cutoff"
    t.integer "max_output_tokens"
    t.json "metadata", default: {}
    t.json "modalities", default: {}
    t.datetime "model_created_at"
    t.string "model_id", null: false
    t.string "name", null: false
    t.json "pricing", default: {}
    t.string "provider", null: false
    t.datetime "unlisted_at"
    t.datetime "updated_at", null: false
    t.index ["family"], name: "index_ruby_llm_models_on_family"
    t.index ["provider", "model_id"], name: "index_ruby_llm_models_on_provider_and_model_id", unique: true
    t.index ["provider"], name: "index_ruby_llm_models_on_provider"
  end

  create_table "ruby_llm_tool_calls", force: :cascade do |t|
    t.string "approval"
    t.json "arguments", default: {}
    t.datetime "created_at", null: false
    t.bigint "message_id", null: false
    t.string "message_type", null: false
    t.string "name", null: false
    t.boolean "remote", default: false, null: false
    t.bigint "result_id"
    t.string "result_type"
    t.text "thought_signature"
    t.string "tool_call_id", null: false
    t.datetime "updated_at", null: false
    t.index ["message_type", "message_id"], name: "index_ruby_llm_tool_calls_on_message_type_and_message_id"
    t.index ["name"], name: "index_ruby_llm_tool_calls_on_name"
    t.index ["result_type", "result_id"], name: "index_ruby_llm_tool_calls_on_result_type_and_result_id"
    t.index ["tool_call_id"], name: "index_ruby_llm_tool_calls_on_tool_call_id", unique: true
  end

  create_table "ruby_llm_usages", force: :cascade do |t|
    t.decimal "cache_read_cost", precision: 16, scale: 10
    t.integer "cache_read_tokens"
    t.decimal "cache_write_cost", precision: 16, scale: 10
    t.integer "cache_write_tokens"
    t.bigint "chat_id", null: false
    t.string "chat_type", null: false
    t.datetime "created_at", null: false
    t.decimal "input_cost", precision: 16, scale: 10
    t.integer "input_tokens"
    t.bigint "message_id"
    t.string "message_type"
    t.string "model", null: false
    t.string "operation", null: false
    t.decimal "output_cost", precision: 16, scale: 10
    t.integer "output_tokens"
    t.string "provider", null: false
    t.string "status", null: false
    t.decimal "thinking_cost", precision: 16, scale: 10
    t.integer "thinking_tokens"
    t.decimal "total_cost", precision: 16, scale: 10
    t.datetime "updated_at", null: false
    t.index ["chat_type", "chat_id"], name: "index_ruby_llm_usages_on_chat_type_and_chat_id"
    t.index ["message_type", "message_id"], name: "index_ruby_llm_usages_on_message_type_and_message_id"
    t.index ["status"], name: "index_ruby_llm_usages_on_status"
    t.check_constraint "operation IN ('chat', 'embedding', 'moderation', 'image', 'speech', 'transcription', 'ocr', 'rerank')"
    t.check_constraint "status IN ('pending', 'succeeded', 'failed', 'cancelled')"
  end

  create_table "runs", force: :cascade do |t|
    t.datetime "agent_execution_expires_at"
    t.integer "agent_execution_generation", default: 0, null: false
    t.string "agent_execution_token"
    t.string "app_version"
    t.integer "chat_id", null: false
    t.datetime "created_at", null: false
    t.text "error_summary"
    t.integer "experiment_execution_id"
    t.integer "experiment_id"
    t.datetime "finished_at"
    t.json "input_snapshot_json"
    t.string "operation"
    t.integer "project_id", null: false
    t.string "requested_by"
    t.json "result_summary_json"
    t.string "ruby_llm_version"
    t.datetime "started_at"
    t.string "status"
    t.integer "time_to_first_output_ms"
    t.datetime "updated_at", null: false
    t.index ["chat_id"], name: "index_runs_on_chat_id"
    t.index ["experiment_execution_id"], name: "index_runs_on_experiment_execution_id"
    t.index ["experiment_id"], name: "index_runs_on_experiment_id"
    t.index ["project_id"], name: "index_runs_on_project_id"
    t.index ["status", "created_at"], name: "index_runs_on_status_and_created_at"
  end

  create_table "tool_definitions", force: :cascade do |t|
    t.string "approval_policy", default: "never", null: false
    t.string "class_identifier", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "enabled", default: true, null: false
    t.string "key", null: false
    t.string "name", null: false
    t.integer "project_id", null: false
    t.json "schema_json", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "enabled"], name: "index_tool_definitions_on_project_id_and_enabled"
    t.index ["project_id", "key"], name: "index_tool_definitions_on_project_id_and_key", unique: true
    t.index ["project_id"], name: "index_tool_definitions_on_project_id"
  end

  create_table "tool_invocations", force: :cascade do |t|
    t.json "arguments_json", default: {}, null: false
    t.integer "attempt_id"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.string "error_class"
    t.string "error_code"
    t.text "error_message"
    t.datetime "finished_at"
    t.boolean "remote", default: false, null: false
    t.json "result_json"
    t.integer "run_id", null: false
    t.datetime "started_at"
    t.string "status", default: "requested", null: false
    t.string "tool_call_id", null: false
    t.integer "tool_definition_id"
    t.string "tool_key", null: false
    t.datetime "updated_at", null: false
    t.index ["attempt_id"], name: "index_tool_invocations_on_attempt_id"
    t.index ["remote"], name: "index_tool_invocations_on_remote"
    t.index ["run_id", "status"], name: "index_tool_invocations_on_run_id_and_status"
    t.index ["run_id", "tool_call_id"], name: "index_tool_invocations_on_run_id_and_tool_call_id", unique: true
    t.index ["run_id"], name: "index_tool_invocations_on_run_id"
    t.index ["tool_definition_id"], name: "index_tool_invocations_on_tool_definition_id"
    t.index ["tool_key"], name: "index_tool_invocations_on_tool_key"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "agent_definitions", "projects"
  add_foreign_key "agent_run_deliveries", "runs"
  add_foreign_key "agent_run_deliveries", "tool_invocations", column: "approval_invocation_id"
  add_foreign_key "approvals", "tool_invocations"
  add_foreign_key "artifacts", "attempts"
  add_foreign_key "artifacts", "knowledge_items"
  add_foreign_key "artifacts", "runs"
  add_foreign_key "attempts", "runs"
  add_foreign_key "chats", "projects"
  add_foreign_key "chats", "ruby_llm_models"
  add_foreign_key "evaluation_case_judgments", "evaluation_case_results", on_delete: :cascade
  add_foreign_key "evaluation_case_judgments", "runs", on_delete: :cascade
  add_foreign_key "evaluation_case_results", "evaluation_dataset_revisions"
  add_foreign_key "evaluation_case_results", "evaluation_executions"
  add_foreign_key "evaluation_case_results", "runs", on_delete: :nullify
  add_foreign_key "evaluation_case_reviews", "evaluation_case_results", on_delete: :cascade
  add_foreign_key "evaluation_comparisons", "evaluation_dataset_revisions"
  add_foreign_key "evaluation_comparisons", "experiments", on_delete: :nullify
  add_foreign_key "evaluation_comparisons", "projects"
  add_foreign_key "evaluation_dataset_case_attachments", "evaluation_dataset_revisions", on_delete: :cascade
  add_foreign_key "evaluation_dataset_revisions", "evaluation_datasets"
  add_foreign_key "evaluation_datasets", "projects"
  add_foreign_key "evaluation_executions", "evaluation_comparisons"
  add_foreign_key "evaluation_executions", "evaluation_dataset_revisions"
  add_foreign_key "evaluation_executions", "experiments", on_delete: :nullify
  add_foreign_key "evaluation_executions", "projects"
  add_foreign_key "experiment_executions", "experiments"
  add_foreign_key "experiment_executions", "projects"
  add_foreign_key "experiments", "projects"
  add_foreign_key "knowledge_chunks", "knowledge_items"
  add_foreign_key "knowledge_collections", "projects"
  add_foreign_key "knowledge_embeddings", "knowledge_chunks"
  add_foreign_key "knowledge_items", "knowledge_collections"
  add_foreign_key "lifecycle_events", "approvals", on_delete: :nullify
  add_foreign_key "lifecycle_events", "artifacts", on_delete: :nullify
  add_foreign_key "lifecycle_events", "attempts", on_delete: :nullify
  add_foreign_key "lifecycle_events", "runs", on_delete: :cascade
  add_foreign_key "lifecycle_events", "tool_invocations", on_delete: :nullify
  add_foreign_key "messages", "chats"
  add_foreign_key "runs", "chats"
  add_foreign_key "runs", "experiment_executions"
  add_foreign_key "runs", "experiments"
  add_foreign_key "runs", "projects"
  add_foreign_key "tool_definitions", "projects"
  add_foreign_key "tool_invocations", "attempts"
  add_foreign_key "tool_invocations", "runs"
  add_foreign_key "tool_invocations", "tool_definitions"
end
