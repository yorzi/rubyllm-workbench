module Learning
  # Small, source-reviewed flow diagrams. HTML keeps the text selectable,
  # accessible and readable in the narrow Turbo panel without a JS renderer.
  class Flow
    DIAGRAMS = {
      "grounded_answer" => {
        stages: [
          [ "Freeze the sources", "Corpus + vector revision → fixed retrieval configuration" ],
          [ "Claim the Run", "Local or provider retrieval → owned query/rerank usage" ],
          [ "Generate structured claims", "RubyLLM with_schema → one model request" ],
          [ "Validate exact quotes", "Known snapshot IDs + source substrings" ],
          [ "Save fenced evidence", "Run / Attempt / JSON Artifact → source links" ],
          [ "Evaluate the saved answer", "Native assertions, reviewer or typed Judge → separate Run" ]
        ],
        branches: [
          "No matching evidence → local refusal → no answer request. Retrieval usage remains separate.",
          "Drift, cancellation or interrupted work → visible outcome, no automatic replay. Citation validity does not verify truth."
        ]
      },
      "agent_execution" => {
        stages: [
          [ "Freeze the task", "Agent revision → Run + dedicated Chat" ],
          [ "Commit the outbox", "AgentRunDelivery in the same transaction" ],
          [ "Claim a lease", "Solid Queue worker → token + generation" ],
          [ "Advance a step", "RubyLLM Agent → tools or model response" ],
          [ "Keep the evidence", "Attempts, citations and report Artifact" ]
        ],
        branches: [
          "Approval needed → persist the pause → human decision → new outbox delivery.",
          "Lease lost → stop stale local writes → recover from persisted steps. An accepted provider request may still have an unknown outcome."
        ]
      },
      "evaluation_workflow" => {
        stages: [
          [ "Freeze the comparison", "Dataset revision + Experiment + model targets" ],
          [ "Run each case", "One Chat, Run and Attempt per model × case" ],
          [ "Check the response", "Transport outcome → JSON Schema validation" ],
          [ "Compare exact output", "Generated JSON vs expected JSON, locally" ],
          [ "Review separately", "Human ratings and optional rubric judge" ]
        ],
        branches: [
          "Provider prompts receive the case input; expected answers and attachments stay out.",
          "Schema validity, exact match and judged quality are separate outcomes. Resume only requests that never started."
        ]
      },
      "knowledge_search" => {
        stages: [
          [ "Prepare the sources", "Extract → checksum → chunks with offsets" ],
          [ "Choose retrieval", "Lexical, semantic or hybrid" ],
          [ "Rank matching chunks", "Compatible vectors + lexical evidence" ],
          [ "Optionally rerank", "Keep the original scores and positions" ],
          [ "Inspect the evidence", "Source, chunk, offsets and degradation reason" ]
        ],
        branches: [
          "Missing semantic prerequisites → explicit lexical fallback.",
          "Retrieval returns source evidence. It does not generate an answer or establish answer quality."
        ]
      }
    }.freeze

    def self.for(key)
      DIAGRAMS[key.to_s]
    end
  end
end
