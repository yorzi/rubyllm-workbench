# RubyLLM Workbench 架构与流程图

图表用于恢复整体关系。它们是面向人的结构说明，不是自动从数据库 schema
生成的图；新增实体、状态、队列或 provider 边界时必须同步维护。

更新时间：2026-09-16
当前实现：M0–M3 核心闭环

## 1. 系统总览：人从哪里进入，证据在哪里落下

```mermaid
flowchart LR
    Human["人 / 本地开发者"] --> Web["Rails Web Shell"]

    subgraph UI["工作台入口"]
      Projects["Projects"]
      Models["Model Explorer"]
      Chat["Project Chat"]
      Tools["Tool Lab"]
      Experiments["Experiment Workspace"]
      Runs["Global Run History / Inspector"]
    end

    Web --> Projects
    Web --> Models
    Web --> Chat
    Web --> Tools
    Web --> Experiments
    Web --> Runs

    subgraph Rails["Rails application"]
      RunExecutor["Ai::RunExecutor"]
      ExperimentExecutor["Ai::ExperimentExecutor"]
      ChatExecutor["Ai::ChatExecutor"]
      StructuredExecutor["Ai::StructuredExecutor"]
      ToolRegistry["Ai::ToolRegistry"]
      ToolRecorder["Ai::ToolInvocationRecorder"]
      ApprovalService["Ai::ApprovalService"]
      Queue["Solid Queue / ChatResponseJob"]
      DB[("SQLite + RubyLLM ActiveRecord")]
    end

    Chat --> RunExecutor
    Tools --> ToolRegistry
    Experiments --> ExperimentExecutor
    Runs --> DB
    RunExecutor --> ToolRegistry
    RunExecutor --> DB
    RunExecutor --> Queue
    ExperimentExecutor --> StructuredExecutor
    StructuredExecutor --> Queue
    Queue --> ChatExecutor
    ChatExecutor --> ToolRecorder
    ChatExecutor --> DB
    ApprovalService --> Queue
    ApprovalService --> DB
    ToolRecorder --> DB

    subgraph RubyLLM["RubyLLM boundary"]
      Conversation["Chat / Message persistence"]
      ProviderAdapter["Provider abstraction"]
      RubyTools["Ruby-defined tools"]
    end

    ChatExecutor --> Conversation
    ChatExecutor --> ProviderAdapter
    ToolRegistry --> RubyTools
    ProviderAdapter --> Providers["Configured providers\nOpenRouter, etc."]
    Conversation --> DB

    classDef current fill:#e9e7ff,stroke:#6558d3,color:#211b4d;
    class Chat,Tools,Runs,RunExecutor,ChatExecutor,ToolRecorder,ApprovalService current;
```

读图方式：

- 人只接触工作台入口；provider SDK/HTTP 不应该从 controller 旁路进入。
- `Run` 是连接 UI、队列、RubyLLM 和数据库的核心证据节点。
- Tool Lab 管的是 allowlist 和 schema；实际调用由 ChatExecutor/RubyLLM 产生，
  再由 ToolInvocationRecorder 标准化。
- M4 Knowledge 和 M5 Agent 不在这张当前图中作为已实现模块出现。

## 2. 带审批的 Chat Run 时序

```mermaid
sequenceDiagram
    autonumber
    actor Human as 人
    participant UI as Chat UI
    participant RE as Ai::RunExecutor
    participant DB as SQLite / RubyLLM records
    participant Q as ChatResponseJob
    participant CE as Ai::ChatExecutor
    participant LLM as RubyLLM + Provider
    participant AS as Ai::ApprovalService

    Human->>UI: 输入 prompt，点击 Run
    UI->>RE: enqueue(chat, project, prompt)
    RE->>DB: 创建 queued Run + Attempt
    RE->>DB: 冻结 prompt、tools、schema、approval policy
    RE->>Q: perform_later(run_id)
    Q->>CE: call(run_id)
    CE->>DB: claim Run，启动 Attempt
    CE->>LLM: 配置快照中的工具并 ask(prompt)
    LLM-->>CE: streamed chunks / assistant tool call
    CE->>DB: 保存 Message、usage、Attempt metrics

    alt 工具不需要审批
        CE->>DB: 记录 ToolInvocation = succeeded
        CE->>LLM: 继续会话
        LLM-->>CE: final assistant response
        CE->>DB: Run = succeeded
        DB-->>UI: inspector 显示结果和工具审计
    else 工具需要审批
        CE->>DB: ToolInvocation + pending Approval
        CE->>DB: Run = waiting_for_approval
        DB-->>UI: 刷新后显示待审批调用
        Human->>UI: Approve 或 Deny
        UI->>AS: 写入决定
        AS->>DB: 更新 Approval 和 ToolInvocation
        AS->>LLM: 更新 RubyLLM 会话决定
        AS->>Q: enqueue continuation
        Q->>CE: call(run_id)
        CE->>DB: claim waiting Run，不新增 user prompt
        CE->>LLM: complete()
        LLM-->>CE: tool result / final assistant response
        CE->>DB: Run = succeeded 或 failed
        DB-->>UI: inspector 显示完整时间线
    end
```

关键点：

1. approval 是 Run 的一种真实中间状态，不是前端 loading 文案。
2. continuation 通过已有会话完成，不重复提交原始 prompt。
3. Run claim 防止审批请求和队列 worker 竞争时重复执行。
4. 如果工具抛异常，系统记录安全的 tool-result error 和失败 diagnostic，保留
   可继续阅读的会话结构。

## 3. 数据关系：一次执行为什么有这么多记录

```mermaid
erDiagram
    PROJECT ||--o{ CHAT : owns
    PROJECT ||--o{ EXPERIMENT : defines
    PROJECT ||--o{ TOOL_DEFINITION : enables
    PROJECT ||--o{ RUN : contains
    CHAT ||--o{ MESSAGE : persists
    CHAT ||--o{ RUN : starts
    EXPERIMENT ||--o{ EXPERIMENT_EXECUTION : runs
    EXPERIMENT_EXECUTION ||--o{ RUN : groups
    RUN ||--o{ ATTEMPT : retries
    RUN ||--o{ ARTIFACT : produces
    RUN ||--o{ TOOL_INVOCATION : audits
    ATTEMPT ||--o{ ARTIFACT : may_attach
    ATTEMPT ||--o{ TOOL_INVOCATION : observes
    TOOL_DEFINITION ||--o{ TOOL_INVOCATION : describes
    TOOL_INVOCATION ||--o| APPROVAL : requests

    PROJECT {
      string name
      string slug
      text description
    }
    CHAT {
      bigint project_id
      bigint ruby_llm_model_id
      string title
    }
    RUN {
      bigint project_id
      bigint chat_id
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
    ARTIFACT {
      bigint run_id
      bigint attempt_id
      string kind
      json content_json
      text content_text
    }
```

读图时记住：

- `Message` 记录模型对话内容；`Run` 记录一次执行的边界和状态；二者不是重复表。
- `Attempt` 解释 provider/model 请求和重试；`Artifact` 解释可复用的耐久产物。
- `ToolDefinition` 是“允许什么”；`ToolInvocation` 是“实际发生什么”；`Approval`
  是“人是否允许发生”。
- `input_snapshot_json` 是历史证据的一部分，不能用今天的工具开关反推过去。

## 4. 状态图：哪些状态需要等待，哪些状态已经结束

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

Approval 自己的状态是：

`pending → approved | denied | expired`

ToolInvocation 的状态比 Run 更细：它可能先是 `requested`，等待审批，再进入
`running`、`succeeded`、`denied` 或 `failed`。因此不要只看 Run 的最终 badge 来
判断工具是否实际执行。

## 5. 里程碑图：现在在哪里，下一步是什么

```mermaid
flowchart LR
    M0["M0 Foundation\n已完成"] --> M1["M1 Chat + Runs\n已完成"]
    M1 --> M2["M2 Structured Compare\n已完成"]
    M2 --> M3["M3 Tools + Approval\n核心已完成"]
    M3 --> M3P["M3 Parallel Calls\n下一项"]
    M3P --> M4["M4 Knowledge + RAG\n延期"]
    M4 --> M5["M5 Agents + Research\n延期"]
    M5 --> M6["M6+ Media / Batch / Ops\n延期"]

    classDef done fill:#e7f6ed,stroke:#3a8f5a,color:#174b2b;
    classDef current fill:#e9e7ff,stroke:#6558d3,color:#211b4d;
    classDef next fill:#fff4d6,stroke:#b27a00,color:#654600;
    classDef deferred fill:#f1f2f4,stroke:#89909b,color:#4c535d;
    class M0,M1,M2 done;
    class M3 current;
    class M3P next;
    class M4,M5,M6 deferred;
```

里程碑不是“功能越多越好”的排行榜。每进入下一个阶段，都要先把上一个阶段的
失败边界、可恢复性和证据写清楚；否则新能力只会增加人无法理解的状态数量。
