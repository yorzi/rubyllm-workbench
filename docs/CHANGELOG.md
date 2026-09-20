# 面向人的迭代记录

这里记录“系统对人来说发生了什么变化”。它不是逐 commit 的机器日志；每一条
都应该回答：为什么改、用户看到了什么、证据是什么、还不能宣称什么。

原则上只追加，不静默改写历史。代码细节回到对应 commit 和
[IMPLEMENTATION_MAP.md](../IMPLEMENTATION_MAP.md)。

## 2026-09-20 — M5 Agent continuation 与 outbox 代次 fencing

### 为什么做

之前的边界测试覆盖了 Run lease 与审批恢复扫描，但没有从 durable outbox 参数跑完 Agent job continuation。
检查过程中发现，初始或审批 delivery 首次取得 lease 后，其 continuation 仍携带旧 generation；旧 delivery
也可能在前一 lease 释放后重新取得执行权。

### 变化

- 增加确定性假 Agent 全流程测试：从初始 outbox 投递运行多步成功、批准/拒绝 `save_run_note`，并在过期
  lease 后移除空 assistant 占位、失败旧 Attempt 后继续执行；另验证迟到的 Agent 回复不能覆盖取消状态。
- Agent job 在每次取得 Run lease 后，把当前 generation 与完整 job 参数写入 continuation；execute 和
  approval claim 都要求 generation 精确匹配，拒绝迟到的重复 outbox delivery。
- README、路线图、实现地图、架构图和系统指南现在说明这些本地路径已有自动化覆盖，并保留进程恢复和
  provider-backed 行为的验证边界。

### 验证证据

- `PARALLEL_WORKERS=1 bin/rails db:test:prepare test`：172 tests、1,123 assertions、0 failures、
  0 errors、1 skip。
- RuboCop：177 个文件无 offenses；Zeitwerk eager load 与 `git diff --check` 通过。

### 尚未证明什么

- M5 仍为 `PARTIAL`：恢复路径以确定性假 Agent 和持久化过期 lease 数据验证；Solid Queue 进程终止/重启恢复与真实 provider 调用未验证。
- 本地浏览器 system test 仍受 Selenium driver 无法在 sandbox 内绑定 loopback socket 限制。

## 2026-09-20 — M5 确定性验收覆盖与公开仓库准备

### 为什么做

M5.2 的持久执行骨架此前只有静态检查，无法证明 Agent 快照、跨库投递恢复和迟到 worker
保护的行为。开源准备审计也发现新开发者缺少前端依赖步骤，Docker 示例会公开未认证的单用户
应用，且仓库没有安全报告和贡献入口。

### 变化

- 新增 AgentDefinition、AgentRunExecutor、AgentRunDelivery、dispatcher、Run lease 和
  Agent step/citation summary 的确定性测试；修复 `Run#succeed!` 的旧式 Hash 调用兼容性。
- outbox 幂等依赖数据库唯一索引处理并发 insert；投递 claim 的过期时间现在在确认和重试时
  一并校验，避免过期 worker 使用旧 token 更新投递状态。
- 新贡献者 setup 与 CI 固定使用 `.nvmrc` 的 Node.js 24.21.0，并执行 `npm ci`；CI 新增
  Rails/Vite 生产资源构建门槛。
- Docker 构建阶段使用同版本 Node.js 安装锁定的前端依赖；示例限制到 `127.0.0.1`，明确镜像
  仅适用于可信的单用户环境。新增贡献指南和漏洞报告说明。
- 忽略仓库根目录的内部需求材料目录，并把历史文档改为自足的产品与实现描述。

### 验证证据

- `PARALLEL_WORKERS=1 bin/rails db:test:prepare test`：167 tests、1,070 assertions、
  0 failures、0 errors、1 skip。
- RuboCop（177 个文件）、Zeitwerk、Bundler Audit、Brakeman（79 checks、0 warnings）、
  CI YAML 解析、`npm ci` 和生产 Rails/Vite 资源预编译通过。
- 浏览器 system test 已建立 Projects 创建流程，但本地执行环境拒绝 Selenium 的回环 socket
  绑定，无法完成断言；CI hosted Ubuntu runner 的浏览器驱动未在本地复现。
- 本地 Docker image build 因 sandbox 无法连接 Docker socket。提权后构建开始，但 Dockerfile
  frontend registry 请求超时；镜像构建尚未由本地或远端 CI 证明。
- 内部产品材料不随应用仓库分发。许可证仍待项目所有者选择；未选定前不能宣称公开复用授权已就绪。

### 尚未证明什么

- M5 仍为 `PARTIAL`：完整 `AgentRunJob#perform` 多步生命周期、Solid Queue 重启恢复演练、真实
  provider search/Agent dogfood，以及被 provider 接收后的重复计费边界尚未验证。
- GitHub CI 尚未在远端运行；Docker 构建也需要能访问官方镜像注册表的环境。

## 2026-09-20 — M5.2 保存的 Agent 与专属 Run

### 为什么做

已有的 Chat 工具与审批只能说明某个对话调用了工具，不能提供可编辑、可复现的 Agent
配置，也不能把一个长任务的多步执行归属到单一 Run。M5.2 先建立版本化定义和持久执行边界。

### 人能看到的变化

- Project 内增加 Agents 工作区；定义保存 provider/model、instructions、已启用的本地工具、
  allowlisted `web_search` 和受限的 temperature / max output token 选项。修改执行配置会提升 revision。
- Agent 页面可输入 task 并排队；每个 Agent Run 创建专属 Chat、Run、初始 Attempt，冻结 prompt 和
  definition snapshot，编辑或删除模板不改写历史 Run。
- `AgentRunJob` 从 Run 快照重建 RubyLLM Agent，逐步调用 `Agent#step`；工具、审批、citation
  Artifact、provider 工具活动和生命周期 step 记录关联到该 Run。
- 每次 worker 执行先获取有到期时间的数据库租约，续租时校验 owner token 和 generation；重复投递
  不能并发接管，繁忙投递会在租约到期时重排。冻结的本地工具 contract 与当前注册项不一致时，Run 会
  停止并要求用新 contract 启动。
- 内置 `save_run_note` 将 Artifact 与 RubyLLM tool-call id 关联并建立唯一索引，工具结果重放时复用原 Artifact。
- Run inspector 为未终结 Agent Run 提供取消操作；终态转换受行锁保护，迟到的成功/失败不能覆盖 cancelled。
- 审批决定按 Run 类型回到 Chat 或 Agent worker；Agent worker 使用 Rails `ActiveJob::Continuable`
  在 step 边界保存 continuation。

### 证据与边界

- 新增 AgentDefinition 与 Agent recovery migration、Project 范围 CRUD；本轮未运行自动化测试。
- Ruby 文件通过 `ruby -c` 与 RuboCop，Rails routes 显示 Agent Run launch 与 Run cancel 入口，`git diff --check` 通过。
- 新增表的 migration 已应用到本地 `storage/development.sqlite3`；没有运行 Agent 执行测试、provider
  请求或 Solid Queue worker 重启演练；M5.2 仍为
  `PARTIAL`，M5.1 的 provider web-search dogfood 也仍待完成。
- Continuation 按至少一次语义恢复；若进程在 provider 请求与结果写入之间中断，可能再次计费或重放请求。
  内置 note 工具已按 tool-call id 幂等；未来副作用工具、取消竞态和跨 worker 恢复仍需通过测试与演练证明。

## 2026-09-20 — M5.2 执行租约与恢复边界加固

### 为什么做

只在模型响应返回后检查租约，无法阻止旧 worker 写入 RubyLLM transcript、usage 或工具结果。迟到的重复
Job 也可能干扰审批等待；恢复时 RubyLLM 的空 assistant 占位可能被误读成完整回答。

### 变化

- Run 行锁现在保护 Agent 消息、usage、流式 chunk、provider 事件、ToolInvocation 和内置笔记写入；
  每次续跑通过 owner token 和 generation 验证执行权。
- 普通 Job 不能接管等待审批的 Run；审批恢复携带已决定 invocation 和 paused generation，同一轮多项审批
  需要全部决定后才会续跑。
- 短暂数据库错误会触发租约续租重试；无法确认执行权时安排恢复投递。空 assistant 占位会作为中断处理，
  失败 Attempt、清理占位并从 Chat transcript 重试。
- 已被 provider 接受的请求无法撤回；worker 中断后可能再次请求并产生额外费用。审批持久化与 Solid Queue
  入队位于不同数据库，仍存在入队失败窗口。

### 证据与边界

- 新增/改动 Ruby 文件通过 `ruby -c` 与 RuboCop；Agent 路由解析、迁移状态和 `git diff --check` 静态核对通过。
- 未运行测试、provider 调用或 Solid Queue 重启演练；M5.2 与整体 M5 继续标为 `PARTIAL`。

## 2026-09-20 — M5.2 持久投递与过期租约扫描

### 为什么做

Approval/Run 状态保存在 primary SQLite，而 Solid Queue 使用独立数据库。单靠 worker `ensure` 调度恢复无法
覆盖 SIGKILL/OOM；跨库的审批决定与队列入队也无法原子提交。

### 变化

- 初始 Agent Run、审批续跑和运行中恢复意图先在 primary 数据库建立唯一 delivery 记录，再由 dispatcher 投递。
- dispatcher 对队列错误保留记录并退避重试；确认投递前崩溃可能重投，Run lease 与 generation 拒绝陈旧任务。
- 每分钟扫描未领取的 queued Run、过期执行租约和所有审批均已决定的等待 Run，并按时间窗限频补发。
- 开发与生产的 recurring schedule 加入 dispatcher；运行环境需要启动 Solid Queue recurring scheduler。

### 证据与边界

- 本地 schema 增加 `agent_run_deliveries` 表；Ruby 语法、应用/迁移 RuboCop、路由与 diff 静态检查通过。
- 未运行自动化执行测试、队列重启演练或 provider 请求；外部 provider 已接受的请求仍不能撤销，恢复可能产生重复调用与费用。
- M5 仍为 `PARTIAL`，直到恢复路径、审批竞态和 scheduler 运维行为有自动化及实际演练证据。

## 2026-09-20 — M5.1 单次 Run 可选托管网页搜索

### 为什么做

M5 需要从可审计、范围受限的 provider-hosted tool 开始。仓库已经迁到
RubyLLM 2.0 的 stable API，Message 表也能保存 citations 和 server tool
calls；这一切片复用现有 Chat Run 的执行边界，不宣称已经提供 Agent 或多步 Deep Research。

### 人能看到的变化

- Chat 表单增加默认关闭的 per-Run 网页搜索选项；搜索词会发送给所选 provider。
- `input_snapshot` 冻结 provider tool 选择；旧 provider tools 在配置新 Run 时清理。
- provider 步骤可从 assistant Message 展开查看；HTTP(S) 引用显示为安全外链，并另存
  为关联 Run/Attempt 的 `citation_set` Artifact。
- RubyLLM 依赖升级到 stable `2.0.0`；现有消息列承载 citations 与 server tool calls。
- README、系统指南、架构图、实现地图和路线图区分了 M5.1 与未完成的 Agent 生命周期。

### 证据与边界

- `bundle update ruby_llm` 成功，Gemfile 与锁文件均解析到 RubyLLM `2.0.0`。
- 对照 RubyLLM 2.0 provider-tools API 实现；已有数据库列和 Artifact 类型足以承载，无新迁移。
- 实现刚完成时自动化测试与真实 provider 调用都尚未运行。定向测试已补齐，具体模型/protocol 是否支持搜索仍需逐一验证；失败保存在 Run。

### M5.1 后续验证 — 2026-09-20

- 定向覆盖 provider-tool 快照/清除、citation Artifact 脱敏与来源关联，以及历史 Run 的工具步骤隔离。
- 完整 Rails 测试集通过：154 tests、1,003 assertions、0 failures、0 errors、1 skip。
- 未调用真实 provider；provider/model 能否执行并实际返回搜索步骤仍待 dogfood。
- RuboCop 无违规，Bundler Audit 未发现漏洞；Brakeman 的两条 SQL 插值告警经标识符引用与参数绑定修正后清零。

## 2026-09-20 — 公开仓库改为自包含文档

### 为什么做

仓库此前跟踪了一个指向个人目录的外部设计资料链接，并把它当作项目文档入口。
其他开发者克隆仓库后无法打开该路径，也无法仅凭仓库内容理解项目。

### 人能看到的变化

- 删除个人机器路径的符号链接，并忽略仓库根目录下的内部需求材料目录。
- README、实现地图和 `docs/` 现在只依赖本仓库的代码、迁移、现有测试、运行证据与路线图。
- 保留后续维护所需的当前能力、限制和 M5–M8 计划，不把外部资料当作运行依赖。

### 证据与边界

本次检查了文档和源代码引用；自动化测试尚未运行。此变更不代表部署或外部用户验证。

## 2026-09-19 — Project 创建入口接入页面学习层

### 为什么做

页面学习层已经解释 Project 如何组织 Chat、Experiment、Knowledge、Tool 和 Run，
但首次进入 Workbench 的 Projects 列表/创建页面没有相邻的解释入口。用户能创建工作区，
却需要离开页面去查为什么它是后续资源的持有边界、slug 又怎样成为路由身份。

### 人能看到的变化

- Projects 页面右侧 inspector 保留 runtime/credential 信息，并新增 `How Projects work`
  链接；Turbo Frame 说明可从当前页打开并返回。
- 同一 Project boundary 主题现在沿完整路径解释列表与表单、Rails 参数许可、模型校验、
  slug 派生与 `to_param`、嵌套资源归属和每个 Run 冻结的工具策略。
- 解释代码新增 ProjectsController、Projects 表单与 Project 模型片段；仍然只读取注册表
  明确允许的源码范围。

### 验证证据与边界

- TopicRegistry 集成测试检查 Projects 首页入口、Turbo Frame 主题及其代码片段；注册表测试
  继续验证源码引用和 anchor。
- 本地验证：全量 Rails 测试 149 runs / 976 assertions（0 failures、0 errors、1 skip），
  RuboCop 156 files 无 offenses，Zeitwerk eager-load 检查通过。
- 本次只是学习入口和说明覆盖扩展；Project 的数据模型、路由授权能力和执行行为均未改变。
- Project 仍是本地组织边界，不是身份认证、授权或多租户隔离承诺。

## 2026-09-18 — contextual learning coverage expansion

### 为什么做

第一版页面学习层已经把 Chat Run、工具审批和 Knowledge Search 连到源码，但用户仍然
需要离开当前功能页，才能理解模型目录、Chat 创建、Experiment 对比、Run Inspector、
Project 边界，以及 Knowledge 文件/文本是如何进入检索系统的。这会让“功能可用”和
“实现可理解”之间留下断层。

### 人能看到的变化

- Model Explorer、Chat setup、Experiment comparison、Run Inspector、Project boundary、
  Knowledge ingestion 新增稳定主题和源码证据。
- Model、Chat、Experiment、Project、Runs、Knowledge 的实际操作页都出现上下文
  `How this works` 链接；Run 和 Knowledge 页面按阶段提供两个不同主题。
- 说明内容明确区分 browse 与 runnable、ingestion 与 search、Run audit 与 provider
  tracing、schema validity 与 answer quality。

### 验证证据

- TopicRegistry 测试现在覆盖 9 个稳定 key，并验证所有源码片段仍可读取且 anchor 未漂移。
- Integration 测试覆盖六个新增页面入口和六个新增 Turbo Frame 主题面板。
- 本次变更仍然只提供本地实现解释，没有声称 provider SLA、生产部署、模型质量或业务结果。

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

检索目标允许使用应用侧 cosine 或兼容的 SQLite vector extension；不应为了让状态看起来
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
- 没有 benchmark：切换默认值前仍缺性能基准。
- 只验证了 macOS arm64 + OpenRouter 一个 1024 维模型；跨维度、跨 provider 未验证。
- 派生索引表是运行时创建的，不在 `db/schema.rb` 中；它是缓存，可删除重建。

## 2026-09-17 — M4 兼容 provider 的 rerank（可切换、pre/post rank 可检查）

### 为什么做

M4 的产品边界要求 reranking 只能对兼容 provider 开放。此前检索只有第一阶段的
lexical/semantic/hybrid 排序，没有第二阶段，也没有能力门控。这次把 rerank
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
  配置作为能力门控。
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

运行记录需要在 RubyLLM/ActiveSupport instrumentation 可用时映射到 Runs/Attempts，
并用 adapter 隔离不稳定的 payload 字段。此前应用只发出自己的 `ai.*` 事件，没有消费
RubyLLM 2.0 的 `*.ruby_llm` 通知；同时 provider
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

M4 的文件处理目标还要求 OCR/extraction 产生带 provenance 的持久 Artifact。此前 knowledge
只接受粘贴文本，文件没有入口，也没有“这段被索引的文本来自哪个文件、由谁抽取”
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
- `DocumentExtractionJob`：OCR/长流程使用 Active Job；job 内失败只记日志并让
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
的问题。M4 的实现目标包含 embedding、retrieval 和可检查的 evidence，并保持 SQLite-first，
避免为了向量能力提前引入 PostgreSQL/pgvector。本次因此先定义 vector adapter 接口，
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

M4 的完整实现目标同时包含 embedding、检索、rerank、文件引用和 OCR/extraction。
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

## 2026-09-16 — 明确实现文档的职责

### 为什么做

随着实现不断增长，产品方向、planned 工作和运行时文档如果混写，就会出现两种相反
的错误：把未来目标说成当前代码，或者把当前限制误读成产品目标。本次明确当前实现文档
应描述代码、测试与运行证据，并持续保留状态和偏差。

### 一致性工作

- 将本目录 `docs/` 明确为代码仓库内部的当前现实层：它随着功能、证据和偏差增长，
  但不覆盖产品方向、代码或测试。
- 统一使用 `IMPLEMENTED`、`PARTIAL`、`PLANNED`、`DEPRECATED`、`REMOVED` 状态词，
  并把 `LOCAL_VERIFIED`、`OPENROUTER_DOGFOOD` 作为独立证据标签。
- 把架构图拆成 L0/L1/L2、运行时、状态和 milestone 图；已验证路径与未来节点分开，
  避免把 M4/M5 画成当前依赖。
- 扩展文档守护测试，确保状态词、关键组件和图表锚点不会被后续迭代意外删除。

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
