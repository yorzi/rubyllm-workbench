# 面向人的迭代记录

这里记录“系统对人来说发生了什么变化”。它不是逐 commit 的机器日志；每一条
都应该回答：为什么改、用户看到了什么、证据是什么、还不能宣称什么。

原则上只追加，不静默改写历史。代码细节回到对应 commit 和
[IMPLEMENTATION_MAP.md](../IMPLEMENTATION_MAP.md)。

## 2026-09-17 — M4 provider embedding 与 lexical/semantic/hybrid 检索证据

### 为什么做

上一刀把“能搜到”和“语义检索已验证”分开，但 lexical coverage 仍然无法回答语义相近
的问题。Specs 要求 M4 提供 embedding、retrieval 和 inspectable evidence，同时明确
“不要为了向量而提前引入 PostgreSQL/pgvector”。本次因此先定义 vector adapter 接口，
再用 SQLite 内的 Float32 blob + 应用侧 cosine 实现有界语料上的语义检索，并让每一次
降级都给出可检查的原因。

### 人能看到的变化

- Knowledge collection 新增 Embeddings 区：列出已配置 provider 的 embedding model，
  一键 embed/re-embed，并显示 status、model、dimensions、coverage、adapter 和
  最近 embed 时间；可一键 clear embeddings。
- Search evidence 新增 retrieval mode：`lexical`、`semantic`、`hybrid`。结果同时展示
  score、cosine similarity、lexical score、matched terms、source 和字符 offset。
- semantic/hybrid 不可用时，页面明确显示“requested mode → 实际 lexical”和原因，
  不会把 lexical 证据标成语义结果。
- Inspector 新增 embedding 状态块；Evidence boundary 说明区分 lexical 信号、
  cosine similarity、rerank 输出和 LLM answer。

### 实现地图

- 迁移与模型：`knowledge_embeddings`（chunk + model 唯一、dimensions、packed vector、
  content checksum、status、usage metadata）与 `knowledge_collections` 的
  embedding 状态列。
- 服务：`Ai::Knowledge::VectorStore`（adapter 接口 + `sqlite_application_cosine`）、
  `EmbeddingCatalog`（model capability + provider 配置门控）、`Embedder`（批量 embed、
  逐 chunk 回退、partial/failed 状态、secret 过滤）、`Retriever`（三种 mode 与
  score 分量）、`Search`（mode 解析、query embedding、显式降级）。
- 控制器与路由：`KnowledgeEmbeddingsController#create/#destroy`；既有
  `KnowledgeCollectionsController#show` 增加 mode 解析。
- 一致性：把散落四处的 provider key 过滤正则收敛为 `Ai::ErrorText`，并让 `sk-`/`sk_`
  两种前缀都能被 redact。

### 验证证据

- 定向回归覆盖 vector encode/decode、cosine、ranking、零向量与维度不匹配、
  embedding 记录唯一性与 checksum provenance、re-embed 替换、未配置/未知 model 拒绝、
  partial 覆盖、失败状态与 secret redaction、三种 mode 的证据分量、stale checksum
  跳过、降级原因和 Project boundary：新增 30 tests，全套 105 tests、670 assertions、
  0 failures、0 errors、1 skip。
- 真实 provider dogfood（`OPENROUTER_DOGFOOD`）：OpenRouter 免费 embedding model
  `liquid/lfm-2.5-embedding-350m:free` 成功 embed 2 个 chunk（1024 维、130 input
  tokens、1.4s）；同一 query 下语义排序为 SQLite 段落 cosine 0.5373 > Tool approval
  段落 0.2334，hybrid 同时保留 lexical 0.6963 与 cosine 0.5373。单次 semantic 查询
  约 1.7s，其中绝大部分是 query embedding 的网络往返。
- HTTP 渲染检查确认 semantic 结果页、降级提示页、hybrid 结果页与 collection 索引
  均 200；本会话没有可用的 headless browser，因此**没有**执行本次的桌面/390px 视觉
  与 `scrollWidth` 复核；响应式类名沿用既有已验证的页面结构。
- 当前条目状态：embedding + semantic/hybrid 检索 `IMPLEMENTED` ·
  `LOCAL_VERIFIED` + `OPENROUTER_DOGFOOD`；完整 M4 仍为 `PARTIAL`。

### 还没有证明什么

- 没有 rerank、file/Active Storage ingestion、OCR/extraction 与 provenance Artifact。
- 只验证了 OpenRouter 一个免费 embedding model；跨 provider embedding 兼容性、
  维度差异和批量失败语义仍未验收。
- 应用侧 cosine 只适用于有界语料；没有测量大规模 corpus、并发或迁移到
  SQLite vector extension/pgvector 的收益。
- dogfood 只说明本次本地行为，不等于生产部署、provider SLA、公众可用性或业务收益。

## 2026-09-16 — M4 本地文本 Knowledge 基础切片

### 为什么做

M4 Specs 的完整目标同时包含 embedding、检索、rerank、文件引用和 OCR/extraction。
如果先接 provider 或上传链路，容易把“能搜到”和“语义检索已验证”混为一谈。本次先
建立一个 SQLite-first、可复核的最小闭环：来源能入库，chunk 能重复生成，检索能返回
原始证据。

### 人能看到的变化

- Project 新增 Knowledge workspace，可以创建 collection、粘贴 bounded text 并
  查看 source、`ready/failed` 状态、chunk 数量和 checksum 前缀。
- Source 会生成带 position 和 `char_start`/`char_end` 的 deterministic chunks；
  Search evidence 会显示 lexical score、matched terms、source title 和原始 chunk。
- Knowledge 查询是 Project-scoped 的同步产品流，不会创建 Chat Run/Attempt，不会
  偷用 provider，也不把结果包装成 LLM answer。

### 实现地图

- 迁移和模型：`KnowledgeCollection`、`KnowledgeItem`、`KnowledgeChunk`。
- 服务：`Ai::Knowledge::Chunker`（800/120 字符窗口）、`Ingestor`（checksum、事务性
  chunk replacement、状态）和 `Retriever`（精确 token lexical scoring）。
- 页面：`KnowledgeCollectionsController`、`KnowledgeItemsController`、Project
  navigation、collection/source/search views。
- 保护：source 只能通过当前 Project 的 nested route 访问；浏览器没有 URL fetch、
  file upload 或任意代码执行入口。

### 验证证据

- SQLite migration 已应用，定向回归覆盖模型、chunk offset、ingestion replacement、
  ready filtering、retrieval evidence、完整 token 匹配和 Project boundary：11 tests、73 assertions、
  0 failures、0 errors。
- 浏览器 QA 验证了 collection 创建、text ingestion、证据查询和 390px 窄屏；窄屏检查
  的 `scrollWidth` 与 `clientWidth` 相等，原有根页面和默认视口已恢复，临时 loopback
  服务已停止。
- 当前条目状态：本地文本基础 `IMPLEMENTED` · `LOCAL_VERIFIED`；完整 M4 仍为
  `PARTIAL`。

### 还没有证明什么

- 没有 provider embedding、vector similarity、rerank、文件/Active Storage ingestion、
  OCR/extraction 或 provenance Artifact；这些仍是 M4 后续工作。
- 本地 lexical score 不代表语义质量、provider 兼容性、部署结果、公众可用性或业务收益。

## 2026-09-16 — M3 并行 tool-call 应用侧策略与多调用审计

### 为什么做

RubyLLM 已经提供 `with_tool_options(calls:, concurrency:)`，但应用此前没有把并行
意图按 Run 冻结，也没有明确哪些本地工具可以安全并行。继续直接打开并行会把 provider
能力差异、SQLite 写入和工具副作用混成一个未经验证的开关。

### 人能看到的变化

- Tool Lab 新增 Project 级 Tool execution 模式，默认 `sequential`，可显式选择
  `parallel`。
- 每个新 Run 的 Input snapshot 现在记录 requested/effective mode、模型 capability、
  `calls`/`concurrency` 和 fallback reason。
- `parallel` 只有在模型声明 `parallel_tool_calls` 且所有 enabled 工具声明
  `parallel_safe?` 时才生效；否则仍串行执行，并显示可检查的降级原因。
- Run inspector 显示实际 tool execution mode；多个 RubyLLM ToolCall 各自显示独立的
  参数、结果、状态、时长和 lifecycle request/completion 事件。

### 实现地图

- `Project#tool_execution_mode` / `ToolDefinitionsController`：保存 Tool Lab 模式。
- `Ai::ToolExecutionPolicy`：能力和并行安全门控，并生成 Run snapshot 与 RubyLLM 选项。
- `Ai::ChatTooling`：通过 RubyLLM public `with_tool_options` 应用冻结选项。
- `Ai::ToolRegistry` 和两个工具：声明并行安全元数据；`save_run_note` 保持
  sequential-only。
- `Ai::ToolInvocationRecorder`：在 RubyLLM thread callback 下用 mutex 保护本地审计，
  并幂等补齐多个调用的 request/completion 事件。

### 验证证据

- 定向回归：28 tests、175 assertions、0 failures、0 errors。
- 覆盖项目设置、模型 capability 门控、side-effect 工具降级、冻结 options、Tool Lab
  更新，以及两个独立 ToolCall 的审计记录和 lifecycle event keys。
- 浏览器 QA 使用临时 loopback Rails 服务，验证后已停止；没有留下后台或常驻服务。

### 还没有证明什么

- 没有 live provider 返回多个 parallel tool calls 的验收结果；当前 live provider
  兼容性继续标记为 `PARTIAL`。
- 这不是 provider-native tracing、跨 provider SLA、SQLite 高并发承诺或部署结果。

## 2026-09-16 — M3 观测切片：LifecycleEvent 目录与 Run 时间线

### 为什么做

Run、Attempt、工具、审批和 Artifact 记录分别保存了事实，但人仍需要一个按时间
顺序回答“这次执行发生了什么”的入口。本次按
`supporting/OBSERVABILITY_COST_SPEC.md` 的最小事件模型，增加应用侧的本地事件目录；
它是当前实现切片，不是新的 tracing 或外部监控承诺。

### 人能看到的变化

- Run inspector 新增 Lifecycle events 时间线，显示状态推进、首个流式输出、工具/
  审批和 Artifact 事件。
- 审批 continuation 会生成新的 Attempt，保留原始 Attempt 和工具调用的历史边界。
- 事件 payload 只显示允许的 ID、状态、provider/model、时长和错误类别等元数据；
  prompt、工具参数、结果和 Artifact 内容仍从原始记录查看。

### 实现地图

- `LifecycleEvent`：SQLite 持久化事件目录，使用 `event_key` 去重。
- `Ai::LifecycleEventRecorder`：订阅 `ActiveSupport::Notifications`、过滤字段并写入
  事件；Run/Attempt/Artifact model callbacks 和工具/审批 recorder 发出事件。
- `RunsController` / Run inspector：加载并按发生时间展示事件。
- SQLite 外键使用删除时 cascade/nullify，保证 schema reset 和历史关联可重建。

### 验证证据

- 干净测试库 `db:schema:load` 通过。
- 全量本地回归：53 tests、363 assertions、0 failures、0 errors、1 个既有 skip。
- 生命周期专项覆盖顺序、去重、敏感字段不进入 payload、审批事件和 continuation
  新 Attempt。

### 还没有证明什么

- 这是当前应用侧的本地事件目录，不是 provider-native 完整事件流、分布式 tracing、
  成本 dashboard、导出或历史回填。
- 并行 tool calls 的 provider 兼容性仍为 `PARTIAL`；本次没有新增 live provider
  dogfood，也没有部署或公开可用性结论。

## 2026-09-16 — 明确 Specs 基线与项目 `docs/` 双层体系

### 为什么做

随着实现不断增长，Specs 和运行时文档如果被当成同一套东西，就会出现两种相反
的错误：把原始参照线悄悄改成“当前代码是什么”，或者把旧的 planned baseline
误读成“当前功能还不存在”。本次校正明确两者各自的意图，保留它们之间的可追溯
关系。

### 一致性工作

- 保留 [`rubyllm-workbench/ai/`](../rubyllm-workbench/ai/) 和 supporting Specs 作为
  稳定基线；本次没有把当前实现倒灌或改写到 Specs。
- 将本目录 `docs/` 明确为代码仓库内部的当前现实层：它随着功能、证据和偏差增长，
  但不覆盖 Specs、代码或测试。
- 统一使用 `IMPLEMENTED`、`PARTIAL`、`PLANNED`、`DEPRECATED`、`REMOVED` 状态词，
  并把 `LOCAL_VERIFIED`、`OPENROUTER_DOGFOOD` 作为独立证据标签。
- 把架构图拆成 L0/L1/L2、运行时、状态和 milestone 图；已验证路径与未来节点分开，
  避免把 M4/M5 画成当前依赖。
- 扩展文档守护测试，确保两套体系的边界、状态词、关键组件和图表锚点不会被后续
  迭代意外删除。

### 证据与边界

这是文档和一致性校正，不是新的运行时功能。当前 M0–M3 核心仍为
`IMPLEMENTED`；并行 tool-call 兼容性为 `PARTIAL`。统一的 Run/Attempt/Artifact
生命周期事件仍记录为 `PLANNED` 的后续技术工作，不能从现有 inspector 推断为完整
event stream 或 tracing。

## 2026-09-16 — 建立人类理解层

### 为什么做

随着功能和 AI agent 迭代，局部代码会越来越容易超过人的即时理解范围。需要一套
稳定入口，把目标、当前能力、运行时序、数据关系、证据边界和下一步统一呈现。

### 新增内容

- `docs/README.md`：阅读顺序、文档职责、证据标签和每次迭代的同步协议。
- `docs/SYSTEM_GUIDE.md`：产品目标、当前能力地图、概念词汇、常见误读和回归项目
  时的快速问题。
- `docs/ARCHITECTURE.md`：系统总览、带审批 Chat 时序、数据关系、状态图和里程碑图。
- `docs/OPERATIONS.md`：本地启动、provider 配置边界、验证分层、故障解释和安全
  注意事项。
- `test/docs/human_system_docs_test.rb`：只守护文档入口、链接和关键图表锚点，
  不把结构检查冒充内容审核。

### 维护规则

之后每个主题性代码变更都要同步检查系统说明、受影响图表、操作手册和本变更日志。
历史记录只追加；实现状态、OpenRouter dogfood、本地验证和生产结果必须继续分开。

## 2026-09-16 — M3 核心：工具、审批和可检查执行

代码提交：`05781d6 feat: add tool approvals and inspection`

### 为什么做

M2 已经能比较结构化输出，但 Chat 还不能把“模型要求执行一个动作”和“人是否
允许这个动作”表达成耐久状态。M3 把这条人机边界补齐，同时让工具调用可以被
检查，而不是藏在一次 provider 响应里。

### 人能看到的变化

- Project 有 Tool Lab，可以查看两个代码定义工具的 schema、registry key、审批策略
  和 enabled 状态。
- Chat 页面可以看到 tool request、脱敏参数、tool result 和待审批调用。
- Run inspector 新增 Tools 区域，展示调用状态、结果、审批和时长。
- `save_run_note` 的批准会恢复原会话，不会再次追加相同 user prompt。
- 工具异常会留下 tool-result error 和 Run/Invocation diagnostic，而不是破坏聊天
  历史结构。
- 修复了 Run inspector 在 390px 下由 JSON/table 内容造成的横向溢出。

### 实现地图

- allowlist：`Ai::ToolRegistry`、`Ai::ChatTooling`
- 持久化：`ToolDefinition`、`ToolInvocation`、`Approval`
- 执行：`Ai::ChatExecutor`、`Ai::ToolInvocationRecorder`、
  `Ai::ApprovalService`、`ChatResponseJob`
- 页面：Tool Lab、Chat approval panel、Run inspector
- 边界：RubyLLM 仍是 provider/conversation/tool-call 的 API 边界；没有任意本地
  shell/code 执行。

### 验证证据

- 本地：47 tests、265 assertions、0 failures、0 errors；RuboCop 95 files 无
  offense；Zeitwerk、migration、diff check 通过。
- OpenRouter Run #11：真实 `project_snapshot` tool call 成功。
- OpenRouter Run #13：`save_run_note` 先进入 `waiting_for_approval`，批准后由现有
  queue worker continuation，生成 report Artifact；消息计数为 1 user + 2 assistant，
  没有重复 prompt。
- 浏览器：Tool Lab、Chat、Run inspector 在桌面和 390px 视口均无横向溢出；原有
  Runs 页面已恢复。

### 还没有证明什么

- 并行 tool calls 的真实 provider 兼容性尚未完成验证。
- M5 Agent、durable research、provider-hosted/server tools 尚未实现。
- 本地 OpenRouter dogfood 不代表部署、公开访问、费用稳定或 provider SLA。

## M2 — 结构化实验与比较

日期：2026-09-16

- Project 可以保存带 revision 的结构化 Experiment。
- 一次 Execution 为多个目标模型创建独立 child Run，失败 child 不会被成功结果
  覆盖。
- schema validation failure 与 transport/provider failure 分开记录。
- OpenRouter Execution #1 和 #2 证明了混合失败保留、重跑和有效 JSON Artifact。

## M1 — Chat、Run 历史和可观测执行

日期：2026-09-16

- 建立 Project Chat、RubyLLM Message 持久化、流式响应、Run/Attempt 生命周期。
- 增加全局 Runs 历史、provider/status/search 过滤和 stable inspector。
- OpenRouter Run #6 证明了本地真实 chat 的持久化输出、Attempt metrics 和 cost
  provenance。

## M0 — Rails 工作台基线

日期：2026-09-15 起

- 建立 Rails 8.1.3.1、Ruby 4.0.2、SQLite、Tailwind、Vite、Hotwire 和 Solid Queue
  基线。
- 建立 Project shell、Model Explorer、空状态、健康检查和测试骨架。

## 文档校正记录

暂无。发现历史记录与代码证据不一致时，在这里追加日期、错误描述、校正依据和
受影响文档，而不是无声修改旧条目。
