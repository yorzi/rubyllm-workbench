# 面向人的迭代记录

这里记录“系统对人来说发生了什么变化”。它不是逐 commit 的机器日志；每一条
都应该回答：为什么改、用户看到了什么、证据是什么、还不能宣称什么。

原则上只追加，不静默改写历史。代码细节回到对应 commit 和
[IMPLEMENTATION_MAP.md](../IMPLEMENTATION_MAP.md)。

## 2026-09-18 — M4 current-reality correction

### 为什么做

近期 M4 的 rerank、文件来源、本地抽取和 provenance 路径已经进入代码与测试，
但多个当前实现入口仍停留在“rerank/文档尚未实现”的旧描述。先校准这条人类理解
基线，才能让后续的页面学习层引用真实能力边界，而不会把历史计划误当成当前事实。

### 当前结论

- 本地 Knowledge 检索、兼容 provider rerank、文件上传/本地抽取和 provenance Artifact
  是已实现的本地路径；对应状态仍不等于完整 M4 或 provider RAG。
- provider file reference lifecycle、真实 OCR dogfood、页级 provenance 和更广的
  cross-provider compatibility 仍是 `PARTIAL` 或 deferred。
- 历史 milestone 记录保留不改写；当前状态同步到 README、SYSTEM_GUIDE、OPERATIONS、
  ARCHITECTURE、IMPLEMENTATION_MAP、TODO，以及 Project/Knowledge 页面上的边界文案。

### 验证证据

- 代码与测试现状以当前 `main` 工作区为准；本次变更只修正文档，没有声称新的部署、
  公众可用性或业务结果。

## 2026-09-17 — sqlite-vector adapter spike（opt-in，默认不变）

### 为什么做

Specs 允许“应用侧 cosine 或兼容的 SQLite vector extension”，但不允许为了让状态看起来
完成就提前引入基础设施。上一刀已经把 adapter 接口留出来了，所以这次是把它接上真实扩展
做一次有边界的验证：证明换 adapter 不需要改 `Embedder`/`Retriever`/`Search`/页面，同时
把新依赖的风险显式暴露出来。

### 人能看到的变化

- `Ai::Knowledge::VectorStore` 现在注册两个 adapter：`sqlite_application_cosine`
  （默认）与 `sqlite_vector_extension`（opt-in spike）。
- 通过设置 `KNOWLEDGE_VECTOR_ADAPTER=sqlite_vector_extension` 并提供
  `SQLITE_VECTOR_PATH`（或 `vendor/sqlite-vector/vector.dylib|so`）启用扩展扫描。
- 扩展不可用时不会静默失败：registry 回退到默认 adapter，Inspector 与结果头显示
  effective adapter 和回退原因。
- 检索证据语义不变：spike 只用 `vector_full_scan` 的 exact cosine，不使用量化近似，
  所以页面上 cosine 的含义与默认 adapter 完全一致。

### 实现地图

- `Ai::Knowledge::VectorStore::Base` 收敛共用的 Float32 pack/unpack 与 cosine；
  两个 adapter 只负责 `key` 与 `rank`。
- `SqliteExtension` 不直接扫 `knowledge_embeddings.vector`：该列混合了不同模型的维度，
  而 sqlite-vector 是“每列一个固定 dimension”且不检查单行 blob 长度，因此它读写一个按
  维度划分的派生索引表 `knowledge_vector_index_<dimension>`，可由源表重建。
- 索引维护：按需对比计数并在事务内重建；每次扫描前对当前连接执行 `vector_init`
  （扩展要求每个连接都初始化）；扩展按连接 `load_extension` 一次并记忆。
- `Ai::Knowledge::Search::Outcome` 暴露 `adapter_key` / `adapter_note`；页面展示。

### 验证证据

- 真实扩展验证：macOS arm64 的 `vector-macos-arm64-1.1.2`（NEON）可以加载；探针确认
  `distance=cosine` 返回 `1 - cosine`，`vector_full_scan` 的 top-k 与 streaming 模式
  都可用。
- 同一 1024 维真实语料、同一 query 向量下，两个 adapter 的排序一致，cosine 差
  ≤ 3.5e-07（Float32 精度内）；单次扫描 2.6ms vs 5.7ms（2 行，仅量级参考）。
- 端到端 `Search`（真实 OpenRouter query embedding + 扩展扫描）得到与默认 adapter
  完全相同的 0.5373 / 0.2334。
- 回退验证：二进制缺失时 fresh process 显示
  `sqlite_vector_extension unavailable (...); using sqlite_application_cosine`。
- 回归：112 tests、700 assertions、0 failures、0 errors、1 skip；zeitwerk 与 rubocop 通过。
- HTTP 渲染检查确认开启扩展时的 semantic/hybrid 页面 200 且显示
  `sqlite_vector_extension`；本会话仍没有 headless browser，未做桌面/390px 视觉复核。

### 还没有证明什么

- 二进制不入库，也不由 Gemfile 管理；Linux VPS/Kamal/Docker/CI 仍需各自提供匹配平台的
  二进制，跨平台分发没有解决。
- 没有量化（INT8/TurboQuant）路径，因此没有 recall、内存和大规模语料的性能结论。
- 没有 benchmark：切换默认值前仍缺 Specs 要求的“先记录性能”。
- 只验证了 macOS arm64 + OpenRouter 一个 1024 维模型；跨维度、跨 provider 未验证。
- 派生索引表是运行时创建的，不在 `db/schema.rb` 中；它是缓存，可删除重建。

## 2026-09-17 — M4 兼容 provider 的 rerank（可切换、pre/post rank 可检查）

### 为什么做

M4 Specs 要求“reranking can be toggled only for compatible providers”。此前检索只有
第一阶段的 lexical/semantic/hybrid 排序，没有第二阶段，也没有能力门控。这次把 rerank
做成可选的第二阶段：它可以改变顺序，但不能替代或改写检索证据。

### 人能看到的变化

- Search evidence 新增 rerank 选择（Off + 已配置的 rerank model）。没有已配置 rerank
  model 时控件不出现，并说明“No configured rerank model; rerank stays off.”
- 应用 rerank 后，每个结果同时显示 `rank N (was M)`、provider rerank score，以及原始
  的 retrieval score / cosine / lexical 分量。
- rerank 不可用或失败时，页面显示“Rerank was not applied — retrieval evidence is
  unchanged”和具体原因；检索结果保持原样，不会消失。
- Inspector 显示本次是否启用 rerank 以及 model。

### 实现地图

- `Ai::Knowledge::RerankCatalog`：以 registry 的 `rerank` output modality + provider
  配置作为能力门控（对应 Specs 的 compatible-provider 要求）。
- `Ai::Knowledge::Reranker`：调用 `RubyLLM.rerank`，返回 (index, score)，错误经
  `Ai::ErrorText` 脱敏。
- `Ai::Knowledge::Search`：rerank 是第二阶段，只重排；`Result` 增加 `rerank_score`
  与 `pre_rank`，Outcome 增加 `rerank_model_id` / `rerank_note` / `rerank_applied`。
- 无新表：rerank 是请求范围内的证据重排，不落库；原始 chunk、checksum 与向量仍是事实。

### 验证证据

- 定向回归覆盖 catalog 过滤、未配置/未知 model 拒绝、reranker 排序、secret 脱敏、
  重排后 pre_rank 指回原检索位置、rerank 失败与未选择 model 时证据不变：新增 9 tests，
  全套 122 tests、758 assertions、0 failures、0 errors、1 skip。
- 真实 provider dogfood（`OPENROUTER_DOGFOOD`）：OpenRouter 免费 rerank model
  `nvidia/llama-nemotron-rerank-vl-1b-v2:free` 可用；同一 query 下 lexical 出现
  0.7833 并列，rerank 给出 0.6758 / 0.111 / 0.0009，把 term 密集的 decoy 提到第一位
  （rerank 与语义意图不一致，见下）。
- HTTP 渲染检查确认 rerank 结果页显示 `rank 1 (was 2)`；本会话仍无 headless browser，
  未做桌面/390px 视觉复核。

### 还没有证明什么

- 只验证了 OpenRouter 一个免费 rerank model；不同 rerank model 的质量差异没有基准。
- dogfood 里 rerank 把词面重复但离题的 decoy 排在语义正确的段落之前，说明 rerank 分数
  不等于语义正确性；它只是一层可检查的重排信号。
- 没有持久化 rerank 调用记录，因此没有跨时间对比或成本累计；rerank 让一次查询多了一次
  provider 往返（本次约 +3s）。
- 未验证 Cohere 等其他 rerank provider，也未验证 top_n / 大候选集行为。

## 2026-09-18 — 升级到 RubyLLM 2.0.0.rc4 并按 2.0 方式接 provider 遥测

### 为什么做

Specs 要求“Subscribe to RubyLLM/ActiveSupport instrumentation when available and
map events to Runs/Attempts”，并且要求用 adapter 隔离不稳定的 payload 字段。此前应用
只发出自己的 `ai.*` 事件，完全没有消费 RubyLLM 2.0 的 `*.ruby_llm` 通知；同时 provider
托管的工具调用没有被标记成 remote。借升级到 2.0.0.rc4 的机会把这两件事补齐。

### 人能看到的变化

- Run inspector 的 Lifecycle events 里出现 `ai.provider.*` 事件，`source` 为 `ruby_llm`：
  显示 operation、provider、provider class、model、streaming、input/output tokens、
  finish reason 与失败类别。它们和原有 `ai.*` 应用事件并列，但来源可区分。
- 工具调用如果是 provider 托管/远端执行，会在 Run inspector 上标记
  “provider-executed · remote”。
- RubyLLM 从 2.0.0.rc3 升到 2.0.0.rc4（rc4 只调整了 instrumentation 里
  `provider_class` 的取值，无破坏性变更）。

### 实现地图

- `Ai::RubyLlmInstrumentation`：订阅 `/\.ruby_llm\z/`，只白名单少量标量字段，写
  `ai.provider.chat` / `ai.provider.tool` / `ai.provider.embedding` / `ai.provider.rerank`。
- `Ai::ExecutionContext`（CurrentAttributes）：RubyLLM 通知里的 `chat:` 是它自己的
  `RubyLLM::Chat`，拿不到应用记录，所以由 executor 在执行期间发布 run/attempt，
  adapter 用这个上下文关联，而不是去猜 payload 内部结构。
- `Ai::LifecycleEventRecorder.persist`：给非 `ai.*` 起源的事件提供同样的 catalog 校验
  与 payload 白名单写入路径；`source` 可区分 application / ruby_llm。
- `tool_invocations.remote`：来自 RubyLLM 2.0 的 `ToolCall#remote?`，并在页面显式标记。

### 验证证据

- 全套回归：130 tests、784 assertions、0 failures、0 errors、1 skip；zeitwerk 与
  rubocop 通过。
- 真实 provider dogfood（`OPENROUTER_DOGFOOD`）：一次真实 `openrouter/free` chat Run
  产生了 1 条 `ai.provider.chat`（`source=ruby_llm`，831 in / 5 out、finish_reason
  stop），Run inspector 正确渲染；嵌入式/独立进程两种路径都验证过通知确实会触发。
- 复查现有集成方式：`with_schema(name/schema/strict)`、`with_tool_options(calls,
  concurrency)`、`approve/deny/complete`、`chunk.content` 均与 2.0 一致，无需改写。

### 还没有证明什么

- 只消费了 chat/tool 两类事件并只验证了 chat；embedding/rerank 事件没有 Run 可挂，
  按设计不写入生命周期目录（知识流不是 Run）。
- 没有把 provider 事件反向写回 Attempt 的 usage/cost；Attempt 仍以 RubyLLM usage 记录
  为准，两者可能在不同时间点落库。
- `tool_call.ruby_llm` 只在有工具调用时才会出现，本次 dogfood 未覆盖。
- 仍然没有 headless browser，页面结论来自 HTTP 渲染检查。

## 2026-09-18 — M4 文档来源：Active Storage 上传、抽取/OCR 与 provenance Artifact

### 为什么做

M4 Specs 还差一条：“OCR/extraction creates durable artifacts with provenance”。此前
knowledge 只接受粘贴文本，文件没有入口，也没有“这段被索引的文本来自哪个文件、由谁抽取”
的证据。这一刀把文件来源接进来，并且明确区分本地可读文件与需要 provider OCR 的文件。

### 人能看到的变化

- Knowledge collection 新增 “Add file source”：上传文件（限 10 MB），后台 job 抽取，
  然后走既有的 chunking / embedding 流程，上传的文件也能被检索到。
- 文本类文件（txt/md/csv/json/yaml/tsv/log）在本地读取；PDF 与图片必须走已配置的
  OCR model。没有已配置 OCR model 时，页面会说明“只有文本类文件可入库”，上传不支持的
  类型会得到明确失败原因，而不是静默空内容。
- 每次抽取都会写一个 `ocr_document` Artifact 作为 provenance：extractor、filename、
  content type、字节数、页数、provider/model（OCR 时）、blob checksum 与内容 checksum。
- Sources 列表显示文件名、抽取状态与 extractor；可展开查看 provenance 与抽取文本预览。

### 实现地图

- `KnowledgeItem`：`source_kind` 增加 `file`；`has_one_attached :document`；新增
  `extraction_status`（not_required/pending/extracting/ready/failed，enum 带 prefix 以避开
  ActiveRecord 冲突）、`extractor`、`extracted_at`、`extraction_error` 与 metadata。
- `Ai::Knowledge::Extractor`：本地读取或 `RubyLLM.ocr`；`Unsupported` 与 `Error` 分开；
  错误信息经 `Ai::ErrorText` 脱敏。
- `Ai::Knowledge::OcrCatalog`：与 embedding/rerank 一样的 capability + 配置门控。
- `Ai::Knowledge::DocumentIngestor`：抽取 → 写 provenance Artifact → 调既有 `Ingestor`。
- `DocumentExtractionJob`：Specs 要求 OCR/长流程用 Active Job；job 内失败只记日志并让
  item 停在 failed，不影响 web 请求。
- `Artifact`：`run_id` 改为可选并新增 `knowledge_item_id`，因为文档 provenance 不属于任何
  Run；仍然要求至少有一个 owner，且没有 Run 时不发 `ai.artifact.created` 事件。

### 验证证据

- 定向回归覆盖本地抽取、分块后可检索、无 OCR model 时的明确失败、不支持类型失败、
  通过已配置 OCR model 抽取并记录 provider 页数、provider 失败时脱敏：新增 6 tests；
  集成覆盖上传 → enqueue → perform → 可检索与失败路径；全套 138 tests、853 assertions、
  0 failures、0 errors、1 skip；zeitwerk 与 rubocop 通过。
- 真实端到端 dogfood：上传 400 B markdown，抽取为 `local_text`，生成 provenance
  Artifact（blob checksum 与内容 checksum 均在），分块后可用 query 检索到该来源。
- HTTP 渲染检查确认上传表单、provenance 折叠区与状态显示正确；本会话仍无 headless
  browser，未做桌面/390px 视觉复核。

### 还没有证明什么

- 本地环境没有已配置的 OCR provider（registry 里只有 Cohere `parse-v5.0` 带 ocr 能力，
  本项目未配置 Cohere），所以 OCR 路径只有 fake client 的测试证据，没有真实 provider
  dogfood。
- 没有 provider 文件引用（file ref lifecycle）跟踪：上传走的是 Active Storage，没有把
  provider 侧 file id/过期写回记录。
- 没有真实 PDF/图片抽取：本地解析器只处理文本类文件，PDF 需要 OCR 或额外的本地解析库。
- 抽取没有页数/页码到 chunk offset 的映射（provenance 只有整体元信息）。

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
