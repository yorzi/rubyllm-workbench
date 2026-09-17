# RubyLLM Workbench 架构与流程图

这些图是项目内部 `docs/` 的当前实现视图，用来帮助人恢复系统关系。它们不是从
数据库自动生成的 ERD，也不是 Specs 的未来架构宣言；具体字段和行为仍以代码、
迁移、测试和运行证据为准。

更新时间：2026-09-16
当前实现：M0–M3 核心闭环、本地 LifecycleEvent 目录、并行策略切片和 M4 本地文本基础 `IMPLEMENTED`
当前图表范围：已验证的本地运行路径；未来节点全部显式标为 `PLANNED`
校准依据：routes、models、migrations、jobs、services、测试、M3 OpenRouter
dogfood（Run #11、Run #13）和 M4 Knowledge 本地回归

## 读图规则

- 先看 L0，得到系统边界；再看 L1，定位代码职责；最后按问题查看数据、时序或状态图。
- `Run` 是一次用户可理解的执行边界；`Attempt` 是其中一次 provider/model 请求。
- `ToolDefinition` 表示“允许什么”，`ToolInvocation` 表示“实际请求了什么”，
  `Approval` 表示“人做了什么决定”。
- `LifecycleEvent` 是按时间索引这些变化的本地元数据记录，不替代原始业务记录，
  也不等同于 provider tracing。
- `ToolExecutionPolicy` 把 Project 的串行/并行意图与 RubyLLM 的
  `calls`/`concurrency` 选项绑定到每个新 Run；不满足能力或安全条件时显式降级。
- `PLANNED` 节点不是当前系统已经存在的运行时组件，不能从图中推断出实现。

## 1. L0 — 当前系统上下文

这张图只回答“谁进入系统、系统经过哪条边界、证据落在哪里”。

```mermaid
flowchart LR
    Human["人 / 本地开发者"] --> UI["Rails HTML / Turbo UI"]
    UI --> App["Rails Workbench"]
    App --> DB[("SQLite\nrecords + knowledge chunks + lifecycle events")]
    App --> Queue["Solid Queue\nChatResponseJob"]
    Queue --> RubyLLM["RubyLLM boundary"]
    App --> RubyLLM
    RubyLLM --> Providers["Configured providers\nOpenRouter, etc."]
    App --> Blobs["Active Storage\nlocal disk"]
```

当前含义：provider 操作从 RubyLLM 边界进入；Run、Message、Attempt、Artifact、工具
调用、审批、KnowledgeItem/KnowledgeChunk 和 LifecycleEvent 等证据落在本地持久化层；队列负责 Chat continuation。远程部署、账号、
外部数据库和公开访问不属于这张当前实现图。

## 2. L1 — 已实现组件如何连接

这张图缩小了节点数量，只保留人需要定位职责的组件。

```mermaid
flowchart TD
    subgraph UI["工作台页面"]
        ProjectUI["Project shell"]
        ChatUI["Project Chat"]
        ExperimentUI["Experiment workspace"]
        ToolUI["Tool Lab"]
        KnowledgeUI["Knowledge workspace"]
        RunUI["Run history / inspector"]
    end

    RunExecutor["Ai::RunExecutor\n(chat submission)"]
    ExperimentExecutor["Ai::ExperimentExecutor\n(structured submission)"]
    StructuredExecutor["Ai::StructuredExecutor"]
    ChatJob["ChatResponseJob"]
    StructuredJob["StructuredResponseJob"]
    ChatExecutor["Ai::ChatExecutor"]
    Tooling["ToolRegistry + ChatTooling\n+ ToolExecutionPolicy"]
    KnowledgeServices["Ai::Knowledge::Chunker + Ingestor\n+ Embedder + Retriever + Search\n+ VectorStore adapter"]
    Audit["ToolInvocationRecorder + ApprovalService"]
    Events["LifecycleEventRecorder\nActiveSupport Notifications"]
    Records["Project / Chat / Run / Attempt\n/ Artifact / tool / Knowledge records / LifecycleEvent"]
    RubyLLM["RubyLLM Chat + embed + provider boundary"]

    ChatUI --> RunExecutor
    ExperimentUI --> ExperimentExecutor
    ToolUI --> Tooling
    KnowledgeUI --> KnowledgeServices
    RunUI --> Records
    RunExecutor --> ChatJob
    ExperimentExecutor --> StructuredJob
    StructuredJob --> StructuredExecutor
    ChatJob --> ChatExecutor
    ChatExecutor --> RubyLLM
    ChatExecutor --> Audit
    Audit --> Records
    RunExecutor --> Events
    ChatExecutor --> Events
    StructuredExecutor --> Events
    Events --> Records
    Tooling --> ChatExecutor
    RunExecutor --> Records
    StructuredExecutor --> Records
    KnowledgeServices --> Records
    KnowledgeServices --> RubyLLM
```

代码职责的简化记忆：

1. Controller 只接收页面意图；`Ai::RunExecutor` 或
   `Ai::ExperimentExecutor` 创建带快照的执行边界。
2. Job 把可恢复执行交给 `Ai::ChatExecutor`；结构化流程再由
   `Ai::StructuredExecutor` 负责 schema、validation 和 Artifact。
3. `ToolRegistry`/`ChatTooling` 只允许代码中已注册的工具；Recorder 和
   `ApprovalService` 把调用及人的决定变成可检查记录。
4. provider/conversation 语义仍由 RubyLLM 承担，应用不旁路调用 provider SDK 或 HTTP。

## 3. L2 — 当前持久化关系

这是当前代码中已落地的主要关系；Message 是 RubyLLM 的持久化记录，不能与 Run
混为一谈。

```mermaid
erDiagram
    PROJECT ||--o{ CHAT : owns
    PROJECT ||--o{ EXPERIMENT : defines
    PROJECT ||--o{ TOOL_DEFINITION : enables
    PROJECT ||--o{ KNOWLEDGE_COLLECTION : owns
    PROJECT ||--o{ RUN : contains
    CHAT ||--o{ MESSAGE : persists
    CHAT ||--o{ RUN : starts
    EXPERIMENT ||--o{ EXPERIMENT_EXECUTION : runs
    EXPERIMENT ||--o{ RUN : defines
    EXPERIMENT_EXECUTION ||--o{ RUN : groups
    RUN ||--o{ ATTEMPT : retries
    RUN ||--o{ ARTIFACT : produces
    RUN ||--o{ TOOL_INVOCATION : audits
    RUN ||--o{ LIFECYCLE_EVENT : explains
    ATTEMPT ||--o{ ARTIFACT : may_attach
    ATTEMPT ||--o{ TOOL_INVOCATION : observes
    ATTEMPT ||--o{ LIFECYCLE_EVENT : annotates
    ARTIFACT ||--o{ LIFECYCLE_EVENT : annotates
    TOOL_INVOCATION ||--o{ LIFECYCLE_EVENT : annotates
    APPROVAL ||--o{ LIFECYCLE_EVENT : annotates
    TOOL_DEFINITION ||--o{ TOOL_INVOCATION : describes
    TOOL_INVOCATION ||--o| APPROVAL : requests
    KNOWLEDGE_COLLECTION ||--o{ KNOWLEDGE_ITEM : contains
    KNOWLEDGE_ITEM ||--o{ KNOWLEDGE_CHUNK : splits

    PROJECT {
        bigint id
        string name
        string slug
        text description
        json settings_json
    }
    CHAT {
        bigint project_id
        bigint ruby_llm_model_id
        string title
    }
    MESSAGE {
        bigint chat_id
        string role
        text content
    }
    EXPERIMENT {
        bigint project_id
        integer revision
        string status
        json schema_json
    }
    EXPERIMENT_EXECUTION {
        bigint experiment_id
        string status
        json input_snapshot_json
    }
    RUN {
        bigint project_id
        bigint chat_id
        bigint experiment_id
        bigint experiment_execution_id
        string operation
        string status
        json input_snapshot_json
        json result_summary_json
    }
    ATTEMPT {
        bigint run_id
        integer sequence
        string provider
        string model_id
        string status
        integer input_tokens
        integer output_tokens
    }
    ARTIFACT {
        bigint run_id
        bigint attempt_id
        string kind
        json content_json
        text content_text
    }
    LIFECYCLE_EVENT {
        bigint run_id
        bigint attempt_id
        bigint artifact_id
        bigint tool_invocation_id
        bigint approval_id
        string name
        string event_key
        string source
        datetime occurred_at
        integer duration_ms
        json payload_json
    }
    TOOL_DEFINITION {
        bigint project_id
        string key
        string class_identifier
        boolean enabled
        string approval_policy
        json schema_json
    }
    TOOL_INVOCATION {
        bigint run_id
        bigint attempt_id
        bigint tool_definition_id
        string tool_call_id
        string status
        json arguments_json
        json result_json
    }
    APPROVAL {
        bigint tool_invocation_id
        string status
        string actor
        datetime requested_at
        datetime decided_at
    }
    KNOWLEDGE_COLLECTION {
        bigint project_id
        string name
        text description
    }
    KNOWLEDGE_ITEM {
        bigint knowledge_collection_id
        string title
        string source_kind
        string source_reference
        text content_text
        string checksum
        string ingestion_status
        json metadata_json
    }
    KNOWLEDGE_CHUNK {
        bigint knowledge_item_id
        integer position
        text content_text
        integer char_start
        integer char_end
        json metadata_json
    }
    KNOWLEDGE_EMBEDDING {
        bigint knowledge_chunk_id
        string provider
        string model_id
        integer dimensions
        binary vector
        string content_checksum
        string status
        json metadata_json
    }
```

读取关系时记住：

- Experiment 定义可复用的结构化任务；Execution 冻结一次运行；child Run 各自保存
  provider/model 结果，所以一个失败不会被另一个成功覆盖。
- `input_snapshot_json` 是历史证据：之后的工具开关、schema 或模型选择不能回写它。
- Artifact 是可复用的产物，不取代原始 Chat、Run、Attempt 和工具审计。
- LifecycleEvent 只保存允许的 ID、状态、provider/model、时长和错误类别等元数据；
  prompt、工具参数、工具结果和 Artifact 内容仍由原始记录负责。`event_key` 用于
  幂等去重，旧 Run 不做迁移后的合成回填。

KnowledgeItem 保存规范化后的文本与 checksum；KnowledgeChunk 保存可重复生成的
内容窗口、位置和字符 offset。KnowledgeEmbedding 按 (chunk, model_id) 唯一保存
provider、dimensions、packed Float32 vector 与 content checksum；检索只在同一
model_id 内比较，stale checksum 会被跳过，所以不同模型或维度的向量不会被混用。
向量读写经过 `Ai::Knowledge::VectorStore` adapter 接口。默认实现是应用侧 cosine，
只适用于有界语料；opt-in 的 `sqlite_vector_extension` 用外部 sqlite-vector 扩展做
exact cosine 扫描。后者不直接扫 `knowledge_embeddings.vector`（该列混合多个模型的
维度，而扩展要求每列一个固定 dimension 且不检查单行 blob 长度），而是读写按维度划分
的派生索引表 `knowledge_vector_index_<dimension>`；该表不在 `db/schema.rb` 中，可
由源表重建。扩展不可用时 registry 回退到默认 adapter 并写明原因。

### 仍未进入当前关系图的扩展

```mermaid
flowchart LR
    Current["当前 Run / Artifact / Knowledge 证据"]
    Current -. "未来扩展" .-> Agent["PLANNED: Agent / durable research"]
    Current -. "未来扩展" .-> Media["PLANNED: Media / batch / export"]
```

这些不是缺失的当前表，而是 Specs 和路线图中的后续方向。

## 4. Runtime — 带审批的 Chat Run

这条路径已经用本地 fake provider 测试，并用 OpenRouter Run #13 做过真实 dogfood。
重点是 continuation 使用已有 RubyLLM 会话，不再次追加原始 user prompt。

```mermaid
sequenceDiagram
    autonumber
    actor Human as 人
    participant UI as Chat UI
    participant RE as Ai::RunExecutor
    participant DB as SQLite / RubyLLM records
    participant Q as ChatResponseJob
    participant CE as Ai::ChatExecutor
    participant LLM as RubyLLM + provider
    participant Audit as Recorder / ApprovalService
    participant Events as LifecycleEventRecorder

    Human->>UI: 输入 prompt，点击 Run
    UI->>RE: enqueue(chat, project, prompt)
    RE->>DB: 原子创建 queued Run + Attempt
    RE->>DB: 冻结 prompt、tools、schema、approval policy、tool options
    RE->>Events: ai.run.created
    RE->>Q: perform_later(run_id)
    Q->>CE: call(run_id)
    CE->>DB: claim Run，启动 Attempt
    CE->>Events: ai.run.started + ai.attempt.started
    CE->>LLM: 配置快照中的工具/options 并 ask(prompt)
    LLM-->>CE: streamed chunks / assistant tool call
    CE->>DB: 保存 Message、usage、Attempt metrics
    CE->>Events: ai.attempt.streaming（首个输出）

    alt 工具需要审批
        CE->>Audit: 请求 ToolInvocation + Approval
        Audit->>DB: pending approval，Run = waiting_for_approval
        Audit->>Events: ai.tool.requested + ai.approval.requested + ai.run.waiting_for_approval
        DB-->>UI: 显示待审批调用
        Human->>UI: Approve 或 Deny
        UI->>Audit: 写入决定
        Audit->>DB: 更新 Approval 和 ToolInvocation
        Audit->>LLM: 更新 RubyLLM 会话决定
        Audit->>Events: ai.approval.decided
        Audit->>Q: enqueue continuation
        Q->>CE: call(run_id)
        CE->>DB: claim waiting Run，创建新的 Attempt，不新增 user prompt
        CE->>Events: ai.run.resumed + ai.attempt.started
        CE->>LLM: complete()
        LLM-->>CE: tool result / final assistant response
        CE->>DB: Run = succeeded 或 failed
        CE->>Events: ai.attempt.succeeded/failed + ai.run.succeeded/failed
        DB-->>UI: inspector 显示完整时间线
    else 无待审批工具
        alt effective_mode = parallel 且 provider 返回多个调用
            CE->>Audit: 并发 callback 逐个记录 ToolInvocation
            Audit->>DB: 每个调用独立保存参数、结果、时长和状态
            Audit->>Events: 每个调用独立 request/completed event_key
            CE->>LLM: 继续会话
            LLM-->>CE: final assistant response
            CE->>DB: Run = succeeded
            CE->>Events: ai.attempt.succeeded + ai.run.succeeded
            DB-->>UI: inspector 显示多个调用和本地时序
        else sequential 或只有一个调用
            CE->>Audit: 记录 ToolInvocation
            Audit->>DB: succeeded invocation
            Audit->>Events: ai.tool.requested / completed
            CE->>LLM: 继续会话
            LLM-->>CE: final assistant response
            CE->>DB: Run = succeeded
            CE->>Events: ai.attempt.succeeded + ai.run.succeeded
            DB-->>UI: inspector 显示结果和工具审计
        end
    end
```

安全边界：Tool Lab 管理的是 Project-scoped allowlist；浏览器输入不能上传 Ruby，
也不能把任意 shell/code 变成工具。参数和结果展示会过滤明显的 secret 字段。

事件记录是同一条本地执行路径的元数据索引；如果事件持久化失败，主 Run/Attempt
执行不会因此失败，原始业务记录仍是事实来源。

## 4.1 Runtime — 并行 tool-call 策略

并行是应用侧的显式 opt-in，不是 provider 能力的默认假设。创建 Chat Run 时，策略
读取 Project 的 `tool_execution_mode`、当前模型的 `parallel_tool_calls` capability 和
enabled registry 工具的 `parallel_safe?` 声明，然后把结果冻结到 `input_snapshot`：

```mermaid
flowchart TD
    Setting["Project Tool Lab\nsequential / parallel"] --> Policy["Ai::ToolExecutionPolicy"]
    Model["RubyLLM model capabilities"] --> Policy
    Tools["Enabled ToolDefinition\nparallel_safe?"] --> Policy
    Policy --> Decision{"条件满足?"}
    Decision -- "是" --> Parallel["effective parallel\ncalls: many\nconcurrency: threads"]
    Decision -- "否" --> Fallback["effective sequential\ncalls: one\nconcurrency: false\n+ fallback_reason"]
    Parallel --> Snapshot["Run input_snapshot"]
    Fallback --> Snapshot
    Snapshot --> ChatTooling["Ai::ChatTooling\nwith_tool_options"]
    ChatTooling --> RubyLLM["RubyLLM conversation loop"]
    RubyLLM --> Recorder["ToolInvocationRecorder\nmutex-protected callbacks"]
    Recorder --> Inspector["Run inspector\nseparate calls + events"]
```

当前两个 registry 工具中，`project_snapshot` 声明可并行，`save_run_note` 创建
Artifact，因此声明为 sequential-only。若使用 parallel 模式但启用了后者，策略会
保留用户的 requested mode，同时把 effective mode 和 fallback reason 写成可检查的
串行结果。此图有本地 deterministic tests 的证据；尚无 live provider 返回多个并行
调用的验收证据。

## 4.2 Runtime — M4 知识检索（lexical / semantic / hybrid）

Knowledge collection 是 Project 下独立的产品数据流，不是一次 Chat Run。用户粘贴
文本后，应用先规范化并计算 SHA-256，再在一个事务内替换该来源的 chunks；embed 时
按 chunk 向 provider embedding model 取向量并落库；查询只读 `ready` 来源，按 mode
返回可检查的证据分量。

```mermaid
flowchart TD
    Human["人"] --> CollectionUI["Knowledge workspace"]
    CollectionUI --> Collection["KnowledgeCollection"]
    CollectionUI --> Item["KnowledgeItem\nnormalized text + checksum"]
    Item --> Ingestor["Ai::Knowledge::Ingestor"]
    Ingestor --> Chunker["Ai::Knowledge::Chunker\n800 chars / 120 overlap"]
    Chunker --> Chunks[("SQLite KnowledgeChunk\nposition + char offsets")]
    CollectionUI --> Embed["embed / re-embed / clear"]
    Embed --> Catalog["Ai::Knowledge::EmbeddingCatalog\ncapability + configuration gate"]
    Catalog --> Embedder["Ai::Knowledge::Embedder\nbatch + per-chunk fallback"]
    Embedder --> RubyLLM["RubyLLM.embed"]
    Chunks --> Embedder
    Embedder --> Vectors[("SQLite KnowledgeEmbedding\nchunk + model_id unique\nFloat32 vector + checksum")]
    CollectionUI --> Query["query + mode"]
    Query --> Search["Ai::Knowledge::Search\nmode resolution + degradation"]
    Search --> Embedder
    Search --> Retriever["Ai::Knowledge::Retriever\nlexical / semantic / hybrid"]
    Chunks --> Retriever
    Vectors --> Retriever
    Retriever --> Adapter["Ai::Knowledge::VectorStore\nsqlite_application_cosine (default)\n+ sqlite_vector_extension (opt-in)"]
    Retriever --> Evidence["score + cosine + lexical\n+ matched terms + source chunk"]
    Evidence --> RerankGate["Ai::Knowledge::RerankCatalog\ncompatible provider gate"]
    RerankGate --> Reranker["Ai::Knowledge::Reranker\nRubyLLM.rerank (optional)"]
    Reranker --> Final["rerank score + pre/post rank\n+ unchanged retrieval evidence"]
```

每次查询的降级都是显式的：semantic/hybrid 需要已选择的 embedding model、已配置的
provider、已存储的向量和一次 query embedding；任一项缺失时 `Search` 返回 lexical
证据并在页面上写明 requested mode 与实际原因。rerank 是可选的第二阶段：只有通过
`RerankCatalog` 的能力门控（registry 的 `rerank` output modality + provider 已配置）
才会调用，它只改变顺序并记录 `rerank_score` 与 `pre_rank`；不可用或失败时保留原证据并
说明理由。该路径不创建 `Run`/`Attempt`，也不宣称文件上传或 OCR。

## 5. Runtime — 状态如何推进

```mermaid
stateDiagram-v2
    [*] --> queued: 创建 Run
    state "waiting_for_approval" as WaitingForApproval
    queued --> running: queue worker claim
    running --> WaitingForApproval: 工具要求人决定
    WaitingForApproval --> running: approve/deny + continuation
    running --> succeeded: 完成且无未决审批
    running --> failed: provider/tool/validation failure
    queued --> failed: job 无法启动
    running --> cancelled: 明确取消
    succeeded --> [*]
    failed --> [*]
    cancelled --> [*]

    note right of WaitingForApproval
        页面可刷新
        Approval 必须可审计
        不应显示为 succeeded
    end note
```

Approval 自己的状态是 `pending → approved | denied | expired`。ToolInvocation 更细，
可能经历 `requested → running → succeeded | failed`，也可能在决定后进入 `denied`。
因此不能只看 Run 的最终 badge 判断工具是否真的执行。

## 6. Runtime — LifecycleEvent 目录如何落地

```mermaid
flowchart LR
    Transition["Run / Attempt / Artifact\n状态变化"] --> Notify["ActiveSupport::Notifications"]
    Tooling["Tool / Approval recorder"] --> Notify
    Notify --> Filter["LifecycleEventRecorder\n固定名称 + payload 白名单"]
    Filter --> Catalog[("SQLite LifecycleEvent")]
    Catalog --> Inspector["Run inspector 时间线"]
    Filter --> Dedupe["event_key 去重"]
    Dedupe --> Catalog
```

当前应用侧事件名称按五组组织：

- Run：`created`、`started`、`resumed`、`waiting_for_approval`、`succeeded`、`failed`；
- Attempt：`started`、`streaming`、`succeeded`、`failed`；
- Tool：`requested`、`completed`；
- Approval：`requested`、`decided`；
- Artifact：`created`。

事件 payload 只允许关联 ID、状态、provider/model、时长、错误类别和验证结果等
元数据，不复制 prompt、工具参数、工具结果或 Artifact 内容。这个目录已经足够
支持当前 Run inspector 的本地时间线，但不构成 provider-native tracing、分布式
事件总线、成本 dashboard 或历史回填。

## 7. Milestone — 基线与当前实现的距离

```mermaid
flowchart LR
    M0["M0 Foundation\nIMPLEMENTED"] --> M1["M1 Chat + Runs\nIMPLEMENTED"]
    M1 --> M2["M2 Structured Compare\nIMPLEMENTED"]
    M2 --> M3["M3 Tools + Approval\nIMPLEMENTED"]
    M3 --> M3P["M3 Parallel Calls\nAPP PATH IMPLEMENTED"]
    M3P --> M4["M4 Knowledge\nEMBEDDING + RETRIEVAL PARTIAL"]
    M4 --> M5["M5 Agents + Research\nPLANNED"]
    M5 --> M6["M6+ Media / Batch / Ops\nPLANNED"]
```

`APP PATH IMPLEMENTED` 的含义是：Project opt-in、能力/安全门控、Run snapshot 和
多调用本地审计路径已经存在并通过 deterministic tests；live provider 的并行返回和
跨 provider 兼容性仍是 `PARTIAL`。M4 当前已实现本地 text collection、chunk、
embedding 记录、SQLite vector adapter 与 lexical/semantic/hybrid 证据，并有
OpenRouter 免费 embedding model 的 dogfood 记录；rerank、file/OCR ingestion 仍未完成，不能
被简化成完整 M4，也不能把当前本地检索误写成 provider RAG。

## 8. 如何保持图表可信

每次新增或改变以下任一项，都要在同一主题迭代中检查本页：实体/迁移、状态转移、
队列 job、provider 边界、工具审批、Artifact 产出或页面入口。更新时：

1. 先对照 Specs，确认目标和约束没有被误读。
2. 再对照代码、测试和实际页面，把已验证路径写成 `IMPLEMENTED` 或 `PARTIAL`。
3. 尚未落地的目标只写 `PLANNED`；被淘汰的入口写 `DEPRECATED` 或 `REMOVED`，
   不要把未来节点画成当前依赖。
4. 在 [CHANGELOG.md](CHANGELOG.md) 记录变更原因、证据和未证明的边界。

图表是帮助人理解当前系统的压缩视图，不是新的事实来源；当图与代码冲突时，应
先修正图或记录偏差，而不是用图替代代码证据。
