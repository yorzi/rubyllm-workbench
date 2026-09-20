# RubyLLM Workbench 架构与流程图

这些图是仓库内的当前实现视图，用来帮助人恢复系统关系。它们不是从数据库自动生成的
ERD，也不是未来架构承诺；具体字段和行为仍以代码、迁移、测试和运行证据为准。

更新时间：2026-09-20
当前实现：M0–M3 核心闭环、本地 LifecycleEvent 目录、并行策略切片和 M4 Knowledge 检索/rerank/文件来源 `IMPLEMENTED`；M5 Agent 持久执行骨架 `PARTIAL`
当前图表范围：已验证的本地运行路径；未来节点全部显式标为 `PLANNED`
校准依据：routes、models、migrations、jobs、services、测试、M3 OpenRouter
dogfood（Run #11、Run #13）、M4 Knowledge 本地回归和 M5 Agent 边界测试

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
    App --> Queue["Solid Queue\nChatResponseJob + AgentRunJob"]
    Queue --> RubyLLM["RubyLLM boundary"]
    App --> RubyLLM
    RubyLLM --> Providers["Configured providers\nOpenRouter, etc."]
    App --> Blobs["Active Storage\nlocal disk"]
```

当前含义：provider 操作从 RubyLLM 边界进入；Run、Message、Attempt、Artifact、AgentDefinition、工具
调用、审批、KnowledgeItem/KnowledgeChunk 和 LifecycleEvent 等证据落在本地持久化层；队列负责 Chat 与 Agent Run continuation。远程部署、账号、
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
        AgentUI["Agent definitions + task form"]
        RunUI["Run history / inspector"]
    end

    RunExecutor["Ai::RunExecutor\n(chat submission)"]
    ExperimentExecutor["Ai::ExperimentExecutor\n(structured submission)"]
    StructuredExecutor["Ai::StructuredExecutor"]
    ChatJob["ChatResponseJob"]
    AgentRunExecutor["Ai::AgentRunExecutor"]
    AgentJob["AgentRunJob\nActiveJob::Continuable"]
    AgentDefinition["AgentDefinition\nproject-scoped revision"]
    StructuredJob["StructuredResponseJob"]
    ChatExecutor["Ai::ChatExecutor"]
    CitationRecorder["Ai::CitationSetRecorder"]
    Tooling["ToolRegistry + ChatTooling\n+ ToolExecutionPolicy"]
    KnowledgeServices["Ai::Knowledge::Chunker + Ingestor\n+ Embedder + Retriever + Search\n+ VectorStore adapter"]
    Audit["ToolInvocationRecorder + ApprovalService"]
    Events["LifecycleEventRecorder\nActiveSupport Notifications"]
    ProviderEvents["Ai::RubyLlmInstrumentation\n*.ruby_llm adapter + ExecutionContext"]
    Records["Project / AgentDefinition / Chat / Run / Attempt\n/ Artifact / tool / Knowledge records / LifecycleEvent"]
    RubyLLM["RubyLLM Agent + Chat + embed + provider boundary"]

    ChatUI --> RunExecutor
    ExperimentUI --> ExperimentExecutor
    ToolUI --> Tooling
    KnowledgeUI --> KnowledgeServices
    AgentUI --> AgentRunExecutor
    AgentRunExecutor --> AgentDefinition
    RunUI --> Records
    RunExecutor --> ChatJob
    ExperimentExecutor --> StructuredJob
    StructuredJob --> StructuredExecutor
    ChatJob --> ChatExecutor
    AgentRunExecutor --> AgentJob
    AgentJob --> RubyLLM
    ChatExecutor --> RubyLLM
    ChatExecutor --> CitationRecorder
    CitationRecorder --> Records
    ChatExecutor --> Audit
    AgentJob --> Audit
    Audit --> Records
    RunExecutor --> Events
    ChatExecutor --> Events
    AgentJob --> Events
    StructuredExecutor --> Events
    Events --> Records
    ProviderEvents --> Records
    RubyLLM -. "instrumentation" .-> ProviderEvents
    Tooling --> ChatExecutor
    RunExecutor --> Records
    StructuredExecutor --> Records
    KnowledgeServices --> Records
    KnowledgeServices --> RubyLLM
```

代码职责的简化记忆：

1. Controller 只接收页面意图；`Ai::RunExecutor`、`Ai::AgentRunExecutor` 或
   `Ai::ExperimentExecutor` 创建带快照的执行边界。
2. Job 把 Chat Run 交给 `Ai::ChatExecutor`，Agent Run 使用 `AgentRunJob` 从快照恢复 RubyLLM
   Agent；结构化流程再由 `Ai::StructuredExecutor` 负责 schema、validation 和 Artifact。
3. `ToolRegistry`/`ChatTooling` 只允许代码中已注册的工具；Recorder 和
   `ApprovalService` 把调用及人的决定变成可检查记录。
4. `CitationSetRecorder` 把响应引用链接到执行它的 Run 和 Attempt；provider 搜索步骤则
   继续保留在 RubyLLM Message 中。
5. provider/conversation 语义仍由 RubyLLM 承担，应用不旁路调用 provider SDK 或 HTTP。

## 3. L2 — 当前持久化关系

这是当前代码中已落地的主要关系；Message 是 RubyLLM 的持久化记录，不能与 Run
混为一谈。

```mermaid
erDiagram
    PROJECT ||--o{ CHAT : owns
    PROJECT ||--o{ EXPERIMENT : defines
    PROJECT ||--o{ AGENT_DEFINITION : defines
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
    AGENT_DEFINITION {
        bigint project_id
        integer revision
        string provider
        string model_id
        text instructions
        json tool_keys_json
        json provider_tools_json
        json options_json
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
- AgentDefinition 是可编辑的 Project 模板；启动 Agent Run 时会把定义 id/revision、模型、
  instructions、工具选择、options 和 prompt 复制进 `Run.input_snapshot_json`。每个 Agent Run
  创建专属 Chat；Run 与 AgentDefinition 不建外键，删除模板不会删除或改写旧 Run。

KnowledgeItem 保存规范化后的文本与 checksum，文本可以来自粘贴，也可以来自 Active Storage
附件（`source_kind: file`）：附件先经 `DocumentExtractionJob` 抽取（本地读取或
provider OCR），抽取结果写成 `ocr_document` Artifact 作为 provenance，再交给同一个
`Ingestor` 分块。Artifact 因此有两种 owner：Run（执行证据）或 KnowledgeItem（文档
provenance），`run_id` 已改为可选。KnowledgeChunk 保存可重复生成的
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
    Current -. "未来扩展" .-> Media["PLANNED: Media / batch / export"]
```

媒体、批量评估和导出不是当前表，仍属于项目路线图后续方向。

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
说明理由。该路径不创建 `Run`/`Attempt`；文件上传和本地抽取属于独立的 Knowledge
ingestion path，并通过 provenance Artifact 表达，provider file reference、真实
OCR/page-level evidence 仍是边界外能力。

## 4.3 Runtime — 保存的 Agent Run

```mermaid
sequenceDiagram
    autonumber
    actor Human as 人
    participant UI as Agent definition page
    participant Launcher as Ai::AgentRunExecutor
    participant DB as SQLite / RubyLLM records
    participant Outbox as AgentRunDelivery
    participant Dispatcher as recurring dispatcher
    participant Queue as Solid Queue / AgentRunJob
    participant Agent as RubyLLM Agent
    participant Provider as Configured provider
    participant Audit as Attempts / tools / approvals / artifacts / events

    Human->>UI: 输入 task
    UI->>Launcher: 用当前 AgentDefinition revision 排队
    Launcher->>DB: 创建专属 Chat、Run、Attempt 和冻结 snapshot
    Launcher->>Outbox: persist execute intent in primary transaction
    Dispatcher->>Outbox: claim due delivery
    Dispatcher->>Queue: enqueue AgentRunJob
    Dispatcher->>Outbox: acknowledge or schedule retry
    Queue->>DB: 从 Run snapshot 重建临时 Agent 配置
    Queue->>DB: ask_later 只持久化一次初始 prompt
    loop 每个 Agent step
        Queue->>Agent: Agent#step
        Agent->>Provider: RubyLLM 请求（需要生成时）
        Provider-->>Agent: Message / tool call / citations
        Agent->>Audit: 记录 Attempt、tool、citation Artifact、step event
        opt 需要人工审批
            Queue->>DB: Run 进入 waiting_for_approval
            Human->>DB: approve 或 deny
            DB->>Outbox: 同一 primary transaction 写 approval continuation
        end
    end
    Human->>DB: 可取消 queued/running/approval-waiting Run
```

`AgentRunJob` 把多步执行交给 Rails 8.1 `ActiveJob::Continuable`，在 step 边界 checkpoint；每次
worker 执行都会从 Run snapshot 和专属 Chat transcript 重建 Agent。Run 行上的随机 owner token、递增
generation 和 5 分钟到期租约阻止同一 Run 被两个有效 owner 同时接管；存活 worker 每 15 秒续租。续租
遇到可识别的临时数据库错误时会重试，仍无法确认 owner 时会安排恢复投递。消息占位与完成记录、usage、
流式输出记录、provider lifecycle event 和当前本地工具数据库写入都会在 Run 行锁内校验 owner；迟到的
通用 Job 不能把 `waiting_for_approval` 改回 `running`。一轮包含多个待审批调用时，只有全部调用都已有
决定，审批续跑才会携带具体 invocation id 与暂停代次接管 Run。

恢复仍遵循至少一次语义：provider 已接受的请求无法因租约丢失而撤销，可能发生重复请求或费用；但旧 owner
迟到的响应不会写入 Chat transcript 或 usage。Agent 启动时会比较冻结的本地工具 schema/policy 快照与当前
注册 contract，发现 drift 就停止，要求创建新 Run。内置只读 `project_snapshot` 无需副作用去重；
`save_run_note` 在 Run 锁内按 RubyLLM tool-call id 唯一复用 Artifact。未来有副作用的工具仍需各自实现
原子租约检查和幂等性。RubyLLM 会先创建空 assistant 占位消息；恢复时若只找到该占位，会将 Attempt
记为失败、删除占位并重新请求，不会把空结果报告为成功。初始 Run、审批续跑与恢复意图先写入 primary
数据库 outbox，再由每分钟 dispatcher 投递到独立 Solid Queue 数据库；dispatcher 也扫描未领取 Run、过期
租约和所有审批均已决定的等待 Run。投递失败会保留并退避重试。队列写入与 outbox 确认无法跨数据库原子
提交，因此确认前崩溃仍可能重复投递；Run lease/generation 会拒绝迟到 owner。开发与生产都必须运行
Solid Queue recurring scheduler，才能持续派发和扫描。执行回归、取消竞态和 worker 重启演练尚未运行，
因此这些恢复保证仍待实测。

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
    queued --> cancelled: 明确取消
    running --> cancelled: 明确取消
    WaitingForApproval --> cancelled: 明确取消
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

来自 provider 的通知走独立路径：RubyLLM 2.0 会发出 `chat.ruby_llm`、
`tool_call.ruby_llm` 等事件，但 payload 里的 `chat` 是它自己的 `RubyLLM::Chat`，
拿不到应用记录。`Ai::ExecutionContext` 因此在执行期间发布当前 Run/Attempt，
`Ai::RubyLlmInstrumentation` 用这个上下文关联，并只白名单少量标量，写成
`ai.provider.*` 事件（`source = ruby_llm`）。没有 Run 可挂的事件（知识流的
embedding/rerank）按设计不写入目录。

当前应用侧事件名称按六组组织：

- Run：`created`、`started`、`resumed`、`waiting_for_approval`、`succeeded`、`failed`、`cancelled`；
- Agent：`step`（step number、definition revision 和状态）；
- Attempt：`started`、`streaming`、`succeeded`、`failed`、`cancelled`；
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
    M3P --> M4["M4 Knowledge\nRETRIEVAL + RERANK + DOCUMENT SOURCES\nLOCAL PATH IMPLEMENTED"]
    M4 --> M5["M5 Agent Runs\nM5.1 search + M5.2 saved agents\nPARTIAL"]
    M5 --> M6["M6 Media\nPLANNED"]
    M6 --> M7["M7 Batch + Evals\nPLANNED"]
    M7 --> M8["M8 Exports + Public Reference\nPLANNED"]
```

`APP PATH IMPLEMENTED` 的含义是：Project opt-in、能力/安全门控、Run snapshot 和
多调用本地审计路径已经存在并通过 deterministic tests；live provider 的并行返回和
跨 provider 兼容性仍是 `PARTIAL`。M4 当前已实现本地 text collection、chunk、
embedding 记录、SQLite vector adapter 与 lexical/semantic/hybrid 证据，并有
OpenRouter embedding/rerank model 的 dogfood 记录，以及文件上传、本地抽取和 provenance
Artifact 的本地回归；provider file references、真实 OCR/page-level evidence 和更广跨
provider 兼容性仍未完成，不能被简化成完整 M4，也不能把当前本地检索误写成 provider RAG。
M5.1 已接入每次 Run 单独 opt-in 的 provider web search，搜索步骤和来源关联到对应 Run，
标准化 citations 另存为 Run Artifact。M5.2 增加了版本化 AgentDefinition、专属 Chat/Run snapshot、
带 generation-fenced lease 的 Agent step worker、transcript/usage/tool 写入保护、工具 contract drift 检查、
幂等笔记 Artifact、审批续跑和取消状态。M5.2 现在有冻结快照、outbox 派发/重试、过期 lease 和审批恢复、
generation fencing、取消终态及 step/citation 时间线关联的确定性自动化测试；假 Agent 也通过
`AgentRunJob#perform` continuation 完成两步成功、approved/denied `save_run_note`、过期 lease 后空响应恢复和
late-response cancellation 路径。
outbox continuation 会携带新 generation，迟到的重复 delivery 会被拒绝。整体 M5 仍是 `PARTIAL`：真实 worker
重启与副作用重放演练和 provider-backed 执行仍待验证。

## 8. 如何保持图表可信

每次新增或改变以下任一项，都要在同一主题迭代中检查本页：实体/迁移、状态转移、
队列 job、provider 边界、工具审批、Artifact 产出或页面入口。更新时：

1. 先对照 README、TODO 和相关代码，确认目标和现有限制。
2. 再对照代码、测试和实际页面，把已验证路径写成 `IMPLEMENTED` 或 `PARTIAL`。
3. 尚未落地的目标只写 `PLANNED`；被淘汰的入口写 `DEPRECATED` 或 `REMOVED`，
   不要把未来节点画成当前依赖。
4. 在 [CHANGELOG.md](CHANGELOG.md) 记录变更原因、证据和未证明的边界。

图表是帮助人理解当前系统的压缩视图，不是新的事实来源；当图与代码冲突时，应
先修正图或记录偏差，而不是用图替代代码证据。
