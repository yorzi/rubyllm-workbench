# 面向人的迭代记录

这里记录“系统对人来说发生了什么变化”。它不是逐 commit 的机器日志；每一条
都应该回答：为什么改、用户看到了什么、证据是什么、还不能宣称什么。

原则上只追加，不静默改写历史。代码细节回到对应 commit 和
[IMPLEMENTATION_MAP.md](../IMPLEMENTATION_MAP.md)。

## 2026-09-27 — Run 事件导出与 M8 容量验证

### 变化

- Run 页面增加 **Download events JSON**：单独下载最新 100 条本地事件，按发生时间和 ID
  升序排列，包含关联 Attempt/Artifact/工具/审批 ID；不加载 Chat、输入快照或 Artifact 内容。
- 导出开始时固定事件 ID 上界，复用复现导出的脱敏和 512 KiB 限制；报告省略数量，
  字节超限时返回 Run 标识和省略原因。下载响应禁止缓存，分享前仍需检查 metadata。
- 补齐 M8 容量边界回归：嵌套集合和深度、值数量、Unicode 文本总量、JSON 转义字节膨胀、
  最近 100 条 Run 消息、最多扫描 1,000 条 Artifact，以及超大 Markdown 草稿降级。
- 修正 TODO 与 implementation map 中“附件校验/导出容量未测试”和“事件导出未实现”的旧状态。

### 验证

- 定向导出回归：14 runs、143 assertions，0 failures/errors/skips。
- 全量 Rails：333 runs、2,892 assertions，0 failures/errors；两个真实 provider 测试按默认设置跳过。
- 浏览器回归：2 runs、9 assertions；272 个 Ruby 文件 RuboCop 通过，Zeitwerk 通过，
  Brakeman 0 warnings/errors，diff whitespace 检查通过。
- 未调用真实 provider、推送代码或发布外部内容；事件导出不代表 provider tracing 或历史补录。
  临时浏览器服务只绑定回环地址，测试结束已退出。

## 2026-09-26 — Rails 升级与 RubyLLM Batch 完整性检查

- 官方版本接口核验：RubyLLM 2.0.0 仍是最新稳定版；Rails 升级到 8.1.4。
- 补齐 CSV 依赖，修复 Ruby 4 环境中的附件校验加载失败；修复复现导出的消息倒序。
- 在未修改的 RubyLLM 2.0.0 中复现 Batch 对重复、负数和越界索引缺少校验的问题。
  Workbench 批量评测增加实例级防护，在任何结果写入前校验整批索引；独立脚本可复现上游行为。
- 本地 Rails 回归：322 runs / 2,818 assertions，无 failures/errors，两个真实 provider 测试跳过。
  浏览器测试：2 runs / 9 assertions。RuboCop、Zeitwerk、Brakeman、依赖审计与生产资源构建通过。
- 没有调用真实 provider、发布上游 issue、推送代码或部署；本地构建 Node 版本与项目 pin 的差异
  以及完整证据见 [升级检查记录](UPGRADE_REVIEW_2026-09-26.md)。

## 2026-09-21 — M5 Agent 生命周期跨切片回归

### 验证

- 将 Agent 定义、执行、审批、delivery/replay、取消与报告相关的 12 个测试文件
  一起运行：47 runs、501 assertions、0 failures、0 errors、0 skips。
- 测试在排除凭据文件的临时副本中运行，Vite test manifest 本地构建；未配置
  provider key，也未发起网络/provider 请求。
- 该结果补充了 M5 本地生命周期覆盖；真实 provider 网页搜索、引用、工具行为及
  hosted CI 仍未验证，M5 继续标记为 `PARTIAL`。

## 2026-09-21 — M8 reproduction export 总量预算

### 变化

- reproduction JSON 升级到 schema v2，限制格式化输出为 512 KiB、总文本为
  100,000 字符、嵌套深度/集合/value 数量，以及 Attempt、工具、事件、Artifact
  和每段 Chat 消息数量；Artifact 扫描最多 1,000 条。
- 导出记录被省略的数量；超出 512 KiB 时只返回 Run 标识、状态和明确的省略原因。这样避免异常 provider metadata 或长 Chat 历史生成无界下载，同时让接收者知道内容不完整。
- Chat 消息仍按 Run 的 message ID 边界选择；超过上限时保留最近 100 条，并写入
  省略数。附件 payload 和 upstream candidate report 仍不导出。
- Markdown issue 草稿设 768 KiB 上限；超限时不附 reproduction JSON 和长文本，只保留标题、类别、Run id 与省略说明。

### 验证边界

- 本次未运行测试或 lint；Ruby `-c` 语法检查与 diff whitespace 检查通过。RubyLLM/provider 没有被调用。格式预算行为尚无新增自动化证据；代表性真实 Run 与隐私审查仍待人工完成。

## 2026-09-21 — M5.7 Chat 入队上下文与 M8 多轮导出

### 变化

- Chat Run 在 Chat 行锁内冻结 RubyLLM 的前序消息结构；同一 Chat 有 queued、running 或 waiting-for-approval Run 时，不再接受新的 Chat Run。
- worker 首次请求 provider 前核对已冻结的历史。队列等待期间消息上下文发生变化时，Run 会在没有 provider 请求的情况下失败并保留该事实。
- Chat Run 的队列拒绝现在会关闭 Run 和首个 Attempt，并返回脱敏后的错误。
- reproduction JSON 现在包含冻结的前序消息，以及由该 Run 写入的 user、assistant、tool 消息；message ID 水位线避免把后续 Run 的内容并入旧导出。
- 消息导出保留 provider 原始内容、工具调用 ID/参数、引用、reasoning signature 和 cache boundary。附件字节不导出，仅保留经过脱敏的附件元数据并明确标记未包含。

### 验证边界

- 本次没有新增或运行测试；Chat context drift、并发入队、队列拒绝、导出水位线和审批续跑的定向自动化证据仍待补齐。
- 没有调用真实 provider。provider 状态、运行时配置变化和模型非确定性不由 reproduction JSON 固定。

### 后续验证更新 — 2026-09-21

- 快照改为直接读取并转换持久化 Message 记录，避免初始化 provider，也避免 RubyLLM memoized Chat 隐藏数据库中的新消息；worker 在比较前 reload Chat。
- 审批等待时也保存当前消息结束水位线，续跑完成后再用新的结束水位线包含同一 Run 的完整消息链。
- 针对上下文冻结/漂移、队列拒绝、同 Chat 重复提交、普通多轮导出、附件字节排除、等待审批时的导出边界及续跑完成导出增加 provider-free 回归：14 runs、135 assertions，0 failures/errors/skips。没有调用 provider。
- 更新后的本地全量 Rails 回归通过：315 runs、2,758 assertions、0 failures/errors、2 个 opt-in provider skips；全量 RuboCop 检查 265 个文件无 offenses，Zeitwerk 通过，Brakeman 8.0.6 为 0 warnings/errors；文档契约测试通过（5 runs、143 assertions）。

## 2026-09-21 — M7 可选 rubric judge 与 M8 签名 URL 脱敏

### 变化

- M7 增加可选自动 rubric judge。它使用冻结的模型和 prompt/schema 版本，为已完成 case 建立独立 Judgment、Run、Attempt 与成本记录；精确 JSON 结果、人工评审和原生成执行指标保持独立。
- 只把 case input、生成输出和 rubric 发送到被选中的 judge provider；expected output、tags 和附件排除。界面披露 provider 请求范围与额外成本。队列拒绝可以在 Run/Attempt 尚未启动时恢复；已启动的超时请求记为 `submission_unknown`，不自动重放，迟到响应不能写入结果。
- M8 reproduction export 现在保留 URL 的非敏感查询参数，同时遮盖通用签名、AWS/GCS 签名和 Azure SAS `sig`，以及敏感 token/credential 值。Markdown upstream 草稿使用同一脱敏逻辑。
- M8 导出只含该 Run 冻结的 prompt，不含此前 Chat 消息；多轮对话复现仍不完整。该边界已同步到使用文档。

### 验证边界

- M7 provider-free 定向检查：24 runs、259 assertions；Ruby 文件 RuboCop 15 个文件无 offenses；Zeitwerk 通过。没有调用 judge provider。
- M8 provider-free 导出与 Markdown 检查：4 runs、112 assertions；Rubocop 3 个 Ruby 文件无 offenses。没有调用 provider。
- 真实 judge provider、评分校准、代表性真实 Run 审查与外部 RubyLLM issue 提交仍未验证。

## 2026-09-21 — M5 failed Run approval cleanup

### Changes

- Failed tool synchronization no longer creates new pending Approval records. The error finalizer now adds ordinary tool errors only for local invocations that were running in the failed Run.
- After the execution lease check, failure closes pending approvals and incomplete tool calls in the same Run transaction. Local pending calls receive a structured denial result; unresolved remote MCP calls receive a local RubyLLM Responses `mcp_approval_response` denial without executing a tool or making another provider request.
- Agent and Chat failure handling keep transcript/tool synchronization, attempt failure and Run failure under the Run lock. A stale lease cannot close another worker's approvals.

### Verification boundary

- Focused provider-free checks passed: 27 runs, 307 assertions, 0 failures/errors/skips. Coverage includes local and remote Agent failure cleanup, stale approval UI/decisions, failure sync without new approvals, and stale lease fencing. Synthetic records were used; no provider request was made.

## 2026-09-21 — M5.6 Preserve uncertain remote tool outcomes

### Why

A review found that an already-approved remote MCP call with no persisted result
could be rewritten as denied when its Run failed. The provider may have executed
the external action before the response was lost, so a synthetic denial would
misstate the record and could invite a duplicate action.

### Changes

- Pending remote approvals still receive a local RubyLLM Responses denial; an
  already-approved remote call with no result keeps its approved decision and
  records `remote_tool_outcome_unknown` without a fabricated protocol response.
- Remote calls cancelled while in progress also retain an explicit unknown
  outcome. The same Chat is blocked from starting another Run and links the user
  to a new Chat, preventing automatic replay of the unresolved call.
- Added `tool_invocations.error_code` so this outcome is queryable and durable.

### Verification boundary

- Focused provider-free coverage: 19 runs, 199 assertions, 0 failures/errors/skips.
  The tests verify approval preservation, no denial result, blocked same-Chat
  continuation, and cancellation outcome labeling. No provider request was made.

## 2026-09-21 — M7 rubric criteria and human ratings

### Changes

- Evaluation cases may define 1–8 bounded rubric criteria in the immutable revision. The rubric is copied to each case result and the local Run evaluation context; it is not added to provider prompts.
- Completed cases accept append-only, allowlisted ratings for every configured criterion. The case view shows rating counts and denominators, including `not_applicable`, without a combined score.
- Ratings remain separate from exact-JSON `passed`, transport/schema outcomes and provider metrics. Existing cases without a rubric continue to support overall verdicts and rationales.

### Verification update

- Focused rubric checks passed: 18 runs, 237 assertions, 0 failures/errors/skips. No provider calls were made.

## 2026-09-21 — M7 evaluation case attachments

### Changes

- Cases can hold project-scoped files in immutable dataset revisions. Uploads and removals create a new revision; retained files are copied by case key, while prior revisions remain inspectable. Deleting a project removes its attachment records and purges associated blobs.
- Uploads are limited to 5 files per case, 10 MB per file, and 50 files / 50 MB per dataset revision, with an explicit MIME allowlist. Filenames, bytes and attachment identifiers stay out of individual and provider Batch prompts; attachment metadata stays in the local Run snapshot.
- The limits apply per revision only. There is no cumulative dataset or project storage quota, so retaining many historical revisions can grow storage usage without a project lifetime cap.

### Evidence boundary

- Focused provider-free attachment checks: 8 runs, 87 assertions, 0 failures/errors/skips. No provider calls were made.

## 2026-09-21 — Release and milestone post-flight checks

### Verification

- Provider-free Rails suite passed: 294 runs, 2,524 assertions, 0 failures/errors and 2 opt-in provider tests skipped. System tests passed: 2 runs, 9 assertions.
- Full RuboCop inspected 256 files with no offenses; Zeitwerk passed. Bundler Audit found no vulnerabilities. `bundle exec brakeman --no-pager` reported 0 warnings.
- A production Docker image built from the current checkout with Node 24.21.0; `npm ci` reported 0 vulnerabilities and Vite completed a clean production build. This is local build evidence, not a hosted CI result.
- No provider calls were made. Live M5/M6/M7 behavior and hosted CI remain unverified.

## 2026-09-21 — M5 本地工具 Agent 能力门控

### 变化

- 选择本地工具的 Agent，必须在 RubyLLM chat registry 中找到精确 provider/model 条目，并由该条目显式声明 `function_calling`。
- 同一门槛在定义保存、Run 创建前和每次 worker 从冻结快照恢复 Agent 时执行；缺失条目或能力声明都会 fail closed。
- 定义页解释准入规则，Agent 详情页在元数据不满足时显示原因并禁用入队按钮。provider-hosted `web_search` 不受这条本地工具门槛影响。
- Registry 声明只支持本地准入判断，不能证明实际 provider/model 接受工具调用；真实 Agent dogfood 仍待完成。

### 验证边界

- 新增确定性本地测试覆盖支持、不支持、缺失 registry 元数据、无本地工具跳过门槛、入队无副作用拒绝和 worker 恢复前拒绝；未调用 provider。

## 2026-09-21 — M5 opt-in Agent dogfood 验收范围

### 变化

- 扩充 OpenRouter Agent opt-in 测试：获批执行时会核对 live Run 的成功状态、多步/hosted-search 证据、成功本地工具、报告与最终 Attempt/冻结 revision/source message/citation 的关联，并渲染 Run inspector 中的报告和 citation 链接。
- M5.3 的真实 Agent Run 仍未验收；扩大测试断言不等于 provider dogfood 结果。

### 验证边界

- 只检查了默认关闭状态下的本地测试；没有设置 opt-in，也没有调用 provider。

## 2026-09-21 — M8 RubyLLM 能力矩阵与兼容性边界

### 变化

- 新增 [CAPABILITIES.md](CAPABILITIES.md)，逐项列出 Chat、structured output、Agent tools、provider web search、embeddings、rerank、OCR、media 与 Batch 的 registry/application 准入条件。
- 将当前 provider-free 路径、历史 OpenRouter dogfood、未验证兼容性分别记录；标明历史 Chat/structured-output/embedding/rerank 验收早于稳定版 2.0.0 pin。
- 明确 web search 没有可靠的 model-level capability 标记；RubyLLM registry 声明不等于 provider/model 服务保证。
- README 与文档索引新增入口；M8 的代表性真实 Run 复核和 upstream 外部流程仍未完成。

### 验证边界

- 文档由本地代码、测试和 TODO 历史记录交叉核对；结构化文档回归为 5 runs、141 assertions、0 failures/errors/skips；没有调用 provider。

## 2026-09-21 — M7 不可变评测 case 标签

### 变化

- Dataset case 接受最多 12 个唯一、非空、每个不超过 40 字符的可选标签；无效类型、重复项、空白填充和超限输入会被拒绝。
- 标签随 immutable dataset revision、comparison/execution snapshot 和子 Run 的本地 evaluation context 保存，并在当前 case、comparison 与 execution 页面展示。
- 标签不会进入 provider prompt，不改变 exact-JSON 比较、transport/schema 统计或质量口径；在本条历史记录形成时，case 附件引用仍未实现。后续实现见本 changelog 的「2026-09-21 — M7 evaluation case attachments」条目。

### 验证边界

- Revision 验证、Evaluation enqueue/snapshot 与页面回归：20 runs、195 assertions、0 failures/errors/skips。
- 修改后的完整 Rails 套件：274 runs、2,323 assertions、0 failures/errors、2 skips；完整 RuboCop 检查 248 个文件无 offense，Zeitwerk eager loading 通过。
- Brakeman 8.0.6 扫描 79 项检查、0 warnings、0 errors；`git diff --check` 通过。只使用本地合成数据，未调用 provider。

## 2026-09-21 — M7 评测 case 的追加式人工评审

### 变化

- 已完成的评测响应可记录 `acceptable`、`needs_work` 或 `inconclusive` 评审，附 self-reported reviewer label 与可选理由；每次提交新增记录，旧记录保留。
- 数据集页在跨模型 case 单元格和单模型执行历史中显示评审及追加入口；Project/dataset/execution/case 逐层限定路由范围。
- 人工评审不改写 exact-JSON `passed`、schema/transport 状态或 token、cost、latency 指标；评审标签未经身份认证，也没有 rubric 聚合或共识分数。
- M7 仍为 `PARTIAL`；配置 provider dogfood、rubric 定义、case 附件/tag 与评审汇总仍未完成。

### 验证边界

- Human review 集成回归：3 runs、38 assertions、0 failures/errors/skips。
- RuboCop 检查 6 个 Ruby 文件无 offense；仅使用本地合成数据，没有调用 provider。

## 2026-09-20 — M5 outbox 确认丢失后的重复投递回归

### 变化

- 新增确定性回归：队列已接受 Agent Job，但 outbox 确认未能落库；delivery claim 过期后 dispatcher 再次投递相同 job 参数。
- 验证 Run lease 在首次执行仍活跃时拒绝重复 owner，成功事务只产生一份 report Artifact；成功后的旧 delivery 进入真实 `AgentRunJob#perform` 时，会在 Agent 重建前退出。该测试覆盖至少一次投递的已知故障窗，没有改变运行时投递语义。
- M5 仍为 `PARTIAL`；真实 provider dogfood 和生产 scheduler 运维仍未验证。

### 验证边界

- Agent dispatcher 与 execution lease 定向测试：8 runs、40 assertions、0 failures/errors/skips。
- 仅使用假队列和本地数据库；没有发起真实 provider 请求，也未验证托管 CI 或生产行为。

## 2026-09-20 — M7 评测指标口径与 Batch 结果分类

### 变化

- Evaluation case 将 provider response、schema validity 与精确 JSON match 分开记录；Batch 明确取消的请求显示为 `cancelled`，schema validation 标为未尝试。
- 执行汇总提供 received/failed、schema valid/invalid、app-observed individual Attempt latency、token coverage，以及按币种区分的 reported/estimated cost；unknown 与 not-attempted 独立列示。
- Provider Batch 在提交前准备失败的 case 明确记为 not attempted，不计入潜在 provider Attempt 的 token/cost 覆盖率。缺失 token usage 保持 unknown，不渲染成零。
- p95 latency 仅在至少 20 个 individual samples 时展示；Batch Attempt 时长包含提交等待和刷新耗时，因此不进入请求延迟分布。
- 同步 README、路线图、实现地图、系统指南和架构图；case tags/attachments、human rubric review 和 provider dogfood 继续标为未完成。

### 验证边界

- Outcome、metrics、Batch workflow、evaluation page 与 human-doc checks：27 runs、313 assertions、0 failures/errors/skips。
- RuboCop 检查 9 个受影响 Ruby 文件无 offense；`git diff --check` 通过。
- 本地 fake provider/测试队列覆盖；没有发起真实 provider 请求。本次没有重跑完整 Rails suite。

## 2026-09-20 — M5 continuation recovery 文档与 M6 media action 状态

### 变化

- 修正系统指南中关于 Agent 审批 continuation 可能永久滞留的旧描述：delivery intent 与决定在主库事务中落入 outbox；dispatcher 会重试并重建缺失投递，恢复仍依赖 recurring scheduler 和 maintenance worker。
- Chat 在模型目录没有对应能力时，明确禁用 image、transcription、video 和 speech 入口并说明原因。
- Assistant 消息 partial 由后台任务等非 Chat controller 上下文渲染时，也会查询并缓存 speech 能力，避免缺失模板局部变量导致 Agent Run 失败。
- M5 仍待真实 provider dogfood；M6 仍待真实媒体 provider 验收和 durable video-job resumption。

### 验证边界

- Agent Run 与媒体 focused regression：22 runs、356 assertions、0 failures/errors/skips。
- 完整 Rails suite：257 runs、2,156 assertions、0 failures/errors、2 skips；RuboCop 检查 238 个文件无 offense；Zeitwerk 与 `git diff --check` 通过。
- 验证使用 fake provider/本地队列；没有发起真实 provider 请求，也未验证托管 CI 或生产行为。

## 2026-09-20 — M8 reproduction export 遮蔽 URL 凭据

### 变化

- Run snapshot 中 `https://user:password@host/path` 与 `postgresql://user:password@host/db` 的 userinfo 现在会被替换成 `REDACTED`，scheme、host、port 与 path 保留。
- 对应检查覆盖 Run JSON 下载、upstream candidate Artifact 和包含 reproduction JSON 的 Markdown 草稿。
- M8 仍为 `PARTIAL`；通用脱敏不能识别任意自定义秘密或私人数据，分享前仍需人工复核。

### 验证边界

- M8 reproduction/candidate 定向测试：7 runs、166 assertions、0 failures/errors/skips。
- 全部使用合成快照，没有调用 provider；没有由此证明任意私有内容都能自动识别。

## 2026-09-20 — M7 Provider Batch 刷新队列准入

### 变化

- Provider Batch 状态刷新现在检查 Active Job 是否接受了 refresh job；拒绝时显示 alert，并保留原 execution、provider ID、case、Run 与 Attempt 状态。
- 只有队列实际接受后，页面才显示 refresh queued。

### 验证边界

- M7 evaluation 定向测试：24 runs、224 assertions、0 failures/errors/skips。
- 队列结果由假 Active Job 返回值控制；实际 refresh job 未运行，没有调用 provider。

## 2026-09-20 — M6 media recovery 边界回归覆盖

### 变化

- 补齐 speech stale queued recovery 与队列拒绝的集成覆盖；Run/Attempt 必须可见失败，且不能开始 provider 工作。
- 补齐 video provider 晚到成功与 stale recovery 竞态覆盖；失败 Run 不得写入 video Artifact。image 同类竞态也有覆盖。
- README、TODO、实现地图和系统说明明确列出四种操作的 queued recovery/enqueue rejection 覆盖，以及 image/video 的 late-success fence。
- M6 仍为 `PARTIAL`；真实 provider dogfood 与 durable video resumption 仍未验收。

### 验证边界

- 定向 speech/media 测试：19 runs、217 assertions、0 failures/errors/skips。
- 完整 Rails suite：256 runs、2,135 assertions、0 failures/errors、2 skips；RuboCop 检查 238 个文件无 offense。
- 所有新增行为使用假队列与假 provider；没有发起真实 provider 请求。

## 2026-09-20 — M7 跨模型 EvaluationComparison 汇总

### 变化

- 一次 comparison 冻结同一 dataset revision、Experiment snapshot 与 2–5 个模型清单；每个模型仍有独立 EvaluationExecution，每个 case 仍有自己的 Run/Attempt。
- Evaluations 页面按模型汇总 pass/fail/pending 与成本状态，并在逐 case 矩阵中链接回原始 Run。未知成本保留为 Unknown。
- Comparison 首版走 individual jobs；已有 Provider Batch 流程仍按单个 Execution 管理。
- `.gitignore` 增加 `config/credentials/*.key`，覆盖 Rails 嵌套 credentials 解密密钥路径。

### 验证边界

- Evaluation service 与 request integration：16 runs、136 assertions、0 failures/errors/skips；使用本地 RubyLLM registry 和测试队列，没有调用 provider。
- RuboCop 与 Zeitwerk 检查通过；`git diff --check` 通过。独立完整回归仍需执行。

## 2026-09-20 — 补齐嵌套 Rails credentials key 忽略规则

### 变化

- Git 现在同时忽略 `config/*.key` 和 `config/credentials/*.key`，与 Docker build context 的密钥排除规则一致。
- 实现地图同步说明：M5 合成状态的浏览器检查已完成，真实 Agent/provider 行为仍待验证。

### 验证边界

- `git check-ignore --no-index` 命中嵌套 production key 路径；根目录 Specs 与生成的 Vite manifest 仍被忽略。
- `git diff --check` 通过（排除 owner 尚未审阅的加密 credentials 工作区文件）；没有读取密钥或发起 provider 请求。

## 2026-09-20 — M7 评测任务队列拒绝处理

### 变化

- Evaluation individual case 与 provider Batch submission 都检查 Active Job 是否实际接受了任务。
- Individual case 入队失败时保留 queued 状态和脱敏错误，保持可重试；后续被接受或 worker 开始处理后清除该错误。
- Provider Batch submission job 在尚未开始时被拒绝，则把本地 execution、case Run 与 Attempt 关闭为 failed；不误记为可能已触达 provider 的 `submission_unknown`。
- Resume 页面按实际接受数显示结果，不把被拒绝的重排任务算作已排队。

### 验证边界

- M5/M7 相关定向回归：28 runs、361 assertions、0 failures/errors/skips。
- Rails 全量测试：247 runs、2,029 assertions、0 failures、0 errors、2 skips；RuboCop 检查 235 个文件无 offense，Zeitwerk eager load 通过。
- 队列拒绝使用假 Active Job 返回值；没有调用 provider，不能证明真实 provider Batch 兼容性。

## 2026-09-20 — M5 合成结果、审批与取消界面复核

### 变化

- Chat 顶部操作按钮在窄屏自动换行；390px 浏览器视口下 Chat 与 Run 页面均无文档级横向溢出。
- Agent Run 状态在审批已经决定、continuation outbox 仍待 worker 处理时显示 `Continuation queued`，避免把“等 worker”误读成“还等人审批”。
- 在隔离 test DB 中通过浏览器检查合成成功报告和 citation、待审批卡片、拒绝后的排队状态，以及取消 Run 后的 expired approval/cancelled tool 状态。

### 验证边界

- `AgentRunFlowTest`：3 runs、93 assertions、0 failures/errors；覆盖审批拒绝后的排队状态和取消 POST 的终态闭合。
- 浏览器使用 Rails test adapter，没有执行 Run worker 或调用 provider。已取消记录由临时测试数据预置；取消 endpoint 的 POST 由集成测试真实提交，浏览器自动化未提交 JavaScript 确认框。
- live provider dogfood 仍未完成；M5 保持 `PARTIAL`。本条只证明这些合成状态的界面呈现。

## 2026-09-20 — M5 队列调度与 Agent outbox 就绪状态

### 变化

- 移除 Runtime 面板静态显示的 `healthy`，改为 `Web responding` 与独立的 `Background jobs` 状态。
- Solid Queue 模式检查近五分钟内带 Agent dispatcher recurring task 的 Scheduler、Dispatcher，以及处理 `maintenance` 队列的 Worker；同时显示到期 Agent outbox 项目数。
- 明确标识 Rails test adapter 不执行后台工作；队列 DB 查询失败时展示不可用状态而不泄露底层异常。
- README、实现地图、系统指南、架构与运维说明补充状态含义和证据边界。

### 验证边界

- 定向测试：12 runs、108 assertions、0 failures/errors；覆盖 test adapter、全就绪和缺失调度/dispatcher/maintenance worker。
- 使用 Rails test 环境只读查询真实 Solid Queue 表时，状态为 `needs_attention`，三个必需进程均未见近期心跳，due Agent deliveries 为 0；没有修改队列记录或调用 provider。
- RuboCop 检查 4 个 Ruby 文件无 offense，`git diff --check` 通过。此信号反映进程心跳与 outbox 本地状态，不证明真实 provider 或生产环境恢复行为。

## 2026-09-20 — M5 Agent 创建与排队页面窄屏浏览器验收

### 变化

- 在隔离的 Rails test 环境中手动创建 Project、保存 revision 1 的 Agent 定义，并排入一个 Agent Run。
- 以 390px 浏览器视口检查 Agent 页面与 Run inspector；文档宽度等于视口内容宽度，没有横向溢出。
- README、路线图和系统指南记录本次浏览器范围及验证边界。

### 验证边界

- 使用 `/private/tmp` 下的临时 SQLite 主库和 Rails test ActiveJob adapter。Run 显示为 `Queued`；worker 未执行，也没有调用 provider。
- 此记录验证页面创建与排队交互，不覆盖实际 Run 输出、引用、审批/取消显示、生产 Solid Queue 调度或真实 provider 兼容性。M5 仍为 `PARTIAL`。

## 2026-09-20 — M6 video 提交证据与 M8 导出脱敏

### 变化

- RubyLLM 2.0.0 的 video-job 提交通知现在把字符串 provider job ID 保存为 `submitted` 生命周期事件，Run 时间线可用于排障识别已提交任务。
- Run reproduction export 对该 ID 脱敏；非 video-job 通知中的同名字段和非字符串值不会被记录。
- 更新 M6 当前状态文档：持久化的 job ID 不恢复 RubyLLM 轮询，也不改变中断任务不自动重放的策略。

### 验证边界

- 全量 Rails 测试：238 runs、1,940 assertions、0 failures、0 errors、2 skips；Ruby 风格检查与 `git diff --check` 均通过。
- 未发起真实 provider 请求；M6 live dogfood、RubyLLM public VideoJob 恢复 API、video usage/cost 规范化仍开放。

## 2026-09-20 — 补齐 M5 hosted approval Agent 续跑验证与 libvips 安装提示

### 变化

- 新增 provider-free Agent Run 流程测试，分别覆盖 MCP hosted approval 的批准和拒绝，从本地 Approval 决定、持久 outbox、`AgentRunJob` continuation 到 RubyLLM 本地生成 `mcp_approval_response`、最终 report Artifact。
- `bin/setup` 会检查 Ruby 是否能加载 `libvips`；缺少时提示 macOS 与 Debian/Ubuntu 安装命令后继续，不自动安装系统包。README、贡献指南和运维文档说明该 native library 只在使用 Active Storage image variants 时需要。
- 发布清单增加双平台、有/无 `libvips` 的人工 setup 验收项。

### 验证边界

- 新增 M5 测试：1 run、33 assertions、0 failures/errors；全量 Rails 测试：234 runs、1,922 assertions、0 failures/errors、2 skips。
- 测试使用合成 RubyLLM MCP ToolCall；没有发起真实 provider 请求。`bin/setup` 尚未在 macOS 与 Debian/Ubuntu 的有/无 `libvips` 环境中人工运行；M5 live dogfood、浏览器视觉验收和 hosted Docker CI 仍未完成。

## 2026-09-20 — M5.5 接入 provider-hosted tool approvals

### 变化

- RubyLLM 持久化的 remote ToolCall 在尚无审批决定和结果时，会进入 Workbench 的待审批生命周期，创建本地 Approval 和 `waiting_for_approval` ToolInvocation。
- Chat approval card 显示该调用由 provider 执行，并与 local tool 明确区分；审批后复用现有 ChatResponseJob 或 Agent approval outbox。
- 批准/拒绝由 RubyLLM 2.0 Responses 转为 `mcp_approval_response` 消息并关联回 ToolCall。识别使用已存的 remote/approval/result 字段，不需要加载 provider 客户端，因此配置缺失时仍可查看已保存的 Chat。

### 验证边界

- 定向测试：工具审批集成与 recorder 共 13 runs、148 assertions、0 failures/errors/skips；覆盖 remote 请求展示、Chat 批准、Agent 拒绝/outbox 以及两种 protocol response 关联。
- 全量 Rails 测试：232 runs、1,882 assertions、0 failures、0 errors、2 skips；RuboCop 检查 232 个文件无 offense；Zeitwerk 与 `git diff --check` 通过。
- 使用合成 RubyLLM ToolCall，没有调用 provider。尚未证明 live provider 返回的审批请求和真实 continuation；M5 仍为 `PARTIAL`。

## 2026-09-20 — 明确参考应用定位与本地开发边界

### 变化

- README 说明项目的开源参考价值位于 Rails 应用层：把 provider 调用变成可追踪的 Run、Attempt、Approval、Artifact 与恢复路径；同时明确它不是 RubyLLM 的替代框架或托管服务。
- M5.5 的技术范围收紧为 RubyLLM 2.0 Responses/MCP approval protocol；本地合成记录覆盖不代表其他 provider-hosted tool 协议兼容，也不代表真实 provider 验收。
- 安全与运维说明指出 provider-hosted 调用由所选 provider 执行，不受本地 Ruby tool registry allowlist 约束。
- `bin/dev` 中 Rails 显式绑定 `127.0.0.1`；ViteRuby 从 `config/vite.json` 读取 loopback host，并把它传给 Vite server，Procfile 使用受支持的 `bin/vite dev` 命令。

### 验证边界

- 浏览器验收准备发现 CLI 不接受 `--host`，且 ViteRuby plugin 会用 `config/vite.json` 覆盖 `vite.config.ts` 的 host；现由 ViteRuby 配置明确绑定 loopback。隔离启动解析为 `127.0.0.1:3036`，随后因沙箱拒绝监听 socket（`EPERM`）退出，未进入视觉验收。
- `bin/dev` 在临时副本中尝试安装缺失的 Foreman，但当前环境无法解析 `rubygems.org`；可用 Node.js 为 `24.14.0`，而项目 pin 为 `24.21.0`，因此 clean-checkout setup 仍未验证。本地 provider 未调用。
- Rails 全量测试为 233 runs、1,889 assertions、0 failures/errors、2 skips；RuboCop 检查 232 个文件无 offense；Zeitwerk、生产资源预编译和 `git diff --check` 通过。视觉验收和 clean-checkout setup 仍开放。

## 2026-09-20 — M5.4 Run 取消时清理待审批工具调用

### 变化

- 取消 Run 时在同一行锁事务中将待处理 Approval 标记为 `expired`，将未完成的 ToolInvocation 标记为 `cancelled`，并保留 finish/error 信息。
- 新增 `ai.approval.expired` 和 `ai.tool.cancelled` 生命周期事件；取消后的审批决定会被终态 Run 拒绝，不会创建 continuation delivery。
- 工具记录同步现在与 Run 锁串行化，并跳过终态 Run，防止 chat inspector 重载时从 RubyLLM 的旧 ToolCall 记录复活审批状态。
- 公开工作流审计修正 Bundler Audit 配置为空注释导致的 YAML 解析失败；配置现在声明空 ignore 列表，不忽略任何 advisory。实现地图和发布 readiness 文案也已对齐当前 Batch 覆盖与外部门槛。

### 验证边界

- M5.4 定向测试：9 runs、85 assertions、0 failures/errors；单进程全量测试：224 runs、1798 assertions、0 failures/errors、2 skips。
- 浏览器系统测试：1 run、3 assertions，通过；测试 Puma 与 ChromeDriver 仅绑定 loopback，退出后对两个端口的连通检查均失败，未发现遗留监听。
- `bin/brakeman --no-pager` 完成，0 个安全警告；Brakeman 最新版检查也通过。Ruby advisory 数据库更新到 commit `44784c295391577f25d198a9205eae4ba73ec4da`（1245 条 advisory），`bin/bundler-audit` 未报告漏洞；`npm audit --audit-level=high` 未报告漏洞。
- 生产资源预编译通过。Docker daemon 不可用，托管 Docker CI 尚未运行；本地 provider 和视觉验收仍未完成。

## 2026-09-20 — M7/M8 provider-free 工作流验证与恢复查询修正

### 变化

- M7 fake Batch 流程测试发现 Store 对账把 JSON `chat_ids` 数组当作 SQL `IN` 集合查询，无法匹配 RubyLLM 的批次记录。现改为按冻结的有序 JSON 数组精确匹配，并用批次流程测试覆盖迟到 Store 记录、顺序刷新、局部取消和逐例 Artifact/Attempt/token 关联。
- 全量测试发现 evaluation recovery 与 execution join 后，对 `started_at` 的未限定查询有歧义；恢复 job 现在显式使用 `evaluation_case_results.started_at`，避免恢复异常被结构化执行器转成 Run 失败、却留下 running case。
- M8 增加候选报告 recorder 与请求流测试，覆盖输入校验、append-only Artifact、Attempt/版本证据、文本脱敏、二进制排除、后续导出过滤、Markdown 下载和 Run/Artifact 作用域。
- README、路线图、实现地图、系统指南和架构说明已同步 M7/M8 本地验证状态；代表性真实 Run 审查和外部 provider 流程仍待完成。

### 验证边界

- M7 fake Batch：5 runs、58 assertions；M8 upstream candidate：6 runs、134 assertions；均无 failures/errors。
- 单进程全量 Rails 测试：223 runs、1779 assertions、0 failures、0 errors、2 skips。
- `bin/rubocop --cache false` 检查 229 个文件，无 offense；`bin/rails zeitwerk:check` 和 `git diff --check` 通过。
- 以上均为本地、provider-free 证据；没有运行真实 provider 请求、手动浏览器视觉验收或托管 CI。Docker daemon 在本机不可用，镜像 build 尚无本地结果。

## 2026-09-20 — M5.3 Agent 报告 Artifact 与开源准备

### 变化

- Agent Run 成功时把最终 assistant 回答保存为 Run-owned `report` Artifact，并与来源 Message、最后一个 Attempt、冻结的 Agent revision 和 citation-set Artifacts 关联；报告写入与 Run 成功状态在同一事务中提交。Run inspector 展示报告并提供引用内链。
- 报告 recorder 按 Run 行锁序列化并发检查；同一来源 Message 重复记录会复用 Artifact。失败或取消不会生成 Agent 报告。
- RubyLLM 固定为 `2.0.0`；根目录 `/specs/` 同时从 Git 索引和 Docker build context 排除，当前没有 Specs 文件被跟踪。
- Docker build context 排除本机 `vendor/bundle`，生产镜像排除 `development` 和 `test` gem 组；CI 加入生产 Docker image build。Docker 示例保持 loopback 绑定并挂载持久化 storage。
- 安全报告说明不再建议在公开 issue 中索要私密联系渠道；仓库未提供 LICENSE，等待项目所有者选择授权条款。

### 验证边界

- M5 定向测试：24 runs、240 assertions、0 failures、0 errors；M6 媒体与恢复定向测试：15 runs、229 assertions、0 failures、0 errors。
- 本地加载到的 `ruby_llm` gem 为 `2.0.0`；`git check-ignore` 确认 `/specs/` 文件与 `vendor/bundle` 被忽略。
- 本机 Docker 客户端无法连接 Docker daemon socket，因此没有本地 image build 结果；新增 CI job 的托管运行仍待发生。
- 真实 Agent/media provider、浏览器视觉验收、GitHub 私密漏洞报告设置和项目授权选择均未验证或完成。

## 2026-09-20 — M6 队列恢复、M7 批次修正与 M8 upstream 候选报告

### 变化

- 修正 Batch 刷新对 RubyLLM `Chat#id` 的错误依赖。现在依赖公开的提交顺序结果契约，校验冻结 case 数量、连续位置和返回条数后再映射。
- 将提交前的 chat/provider/payload 检查留在 `preparing` 阶段；在进入 `submitting` 时再次确认所有 case、Run 与 Attempt 仍可提交。
- stale preparation recovery 先在 execution 行锁内关闭提交入口，再失败未完成 case。对提交结果未知的请求保留 Run/Attempt；周期恢复发现迟到的 RubyLLM 本地批次记录时，会继续处理而不重提。
- 为永久未知但始终没有本地批次 ID 的情况添加明确的本地关闭操作；操作会先警告远端请求可能仍在处理，关闭只失败本地 Run/Attempt，不取消或重提 provider 请求。
- 手动关闭未知 Batch 时，子 Run、Attempt 和 case 结果现在在同一 Run 锁定事务中结束；遇到并发状态变化会回滚整个 execution 关闭，不会留下互相矛盾的终态。
- M6 的 image/video/transcription/speech 失败 Attempt 改为在 Run 锁内和 Run 失败状态一起提交；队列拒绝会立即落为失败，30 分钟未被领取的 queued Run 由恢复 worker 标为 `worker_not_started`，不调用 provider。
- Run inspector 可把人工分类、预期/实际行为、最小复现、回归测试引用及版本证据保存为 append-only report Artifact，并下载包含脱敏复现 JSON 的 Markdown 草稿。后续导出会排除旧候选报告，避免候选内容递归嵌套；文本脱敏增加 AWS access-key ID 和 key assignment 规则。
- 项目已固定 RubyLLM `2.0.0`；仓库和 Docker context 均忽略整个 `/specs/` 目录。

### 本轮核查边界

- 68 个受影响 Ruby 文件通过 `ruby -c`；RuboCop 检查 66 个手写 Ruby 文件无 offense（生成的 `db/schema.rb` 和 `db/queue_schema.rb` 只做语法检查）；`git diff --check` 通过。
- 本轮未运行测试、Rails boot、浏览器验收或 provider 请求；M7 batch 与 M8 candidate 自动化覆盖仍待补，真实 provider 兼容性仍未证明。

## 2026-09-20 — M6 图像生成与音频转录实现切片

### 为什么做

M6 的验收包括 image、speech、transcription 和 video，但仓库只有语音路径。RubyLLM 2.0.0
提供 image-generation 与 transcription 能力标签以及对应 API，因此继续补上无需引入输入图像编辑边界的两条异步路径。

### 变化

- 新增 capability-gated media catalog；图像按 `image_generation`、转录按 `transcription` 能力筛选，
  video 按 RubyLLM 的 video 输出类型筛选，不把 image/audio 输出模态误当成其它操作支持。模型缺少
  provider 配置时，选择项会禁用。
- 新增异步 Image Run，冻结 prompt/provider/model，后台调用 `RubyLLM.paint(count: 1)`，校验返回为
  PNG、JPEG、WebP、GIF 或 AVIF 后保存 Active Storage `image` Artifact，记录 MIME、大小、SHA-256、usage 和 cost。
- 新增音频转录上传和异步 Run。只接受明确列出的常见音频扩展名/MIME，文件限制 25 MB；原始文件保存
  为输入 `audio` Artifact，后台传递 Active Storage Blob 给 RubyLLM，成功后保存 transcript 文本 Artifact。
- 新增异步 Video Run。RubyLLM `animate` 在后台提交/轮询并保存视频 Artifact；RubyLLM 2.0.0 没有标准化
  video usage/cost 字段，因此费用明确显示 unknown。provider job handle 尚未持久化以供恢复。
- 增加 media provider lifecycle 映射、成本类别、Run Inspector 媒体预览/转录文本、可取消状态与
  30 分钟 stale-work 失败恢复。恢复不会自动重放可能已被 provider 接收的请求。
- chat 页在没有 RubyLLM video-output model 时显示 Video unavailable。Specs 已同时从 Git 与 Docker build
  context 排除，并移除 bundler-audit 的虚构 advisory ignore 项；`.DS_Store` 也从 Git 与 Docker
  context 排除。
- Dependabot 开始检查 npm 依赖，CI 增加 high/critical npm audit；Docker 操作说明列出运行时
  `SECRET_KEY_BASE` 要求。RubyLLM initializer 允许 env-only 部署在没有 `RAILS_MASTER_KEY` 时启动，
  只有使用加密 credentials 中的 provider keys 才需要提供 master key。

### 验证边界

- 本轮没有调用真实 provider，也没有运行 image/video/transcription 的自动化或浏览器验收；这三条新路径仍需本地验收。
- RubyLLM 2.0.0 的 API 与模型 capability 来自本机已安装 gem 源码检查；这不证明任何 provider 配置实际可用。
- M6 仍为 `PARTIAL`：新媒体本地验收、durable video-job resumption、标准 video cost/usage 与真实 provider
  dogfood 未完成。开源分发 license 仍需项目所有者选择。

## 2026-09-20 — M7 evaluation 与 M8 reproduction export 首片

### 概览

#### 为什么做

M7 需要把离散 prompt 对比推进为可复查的数据集执行，同时保留普通 Run/Attempt 证据；M8 需要一个
显式、可审阅的单 Run 复现导出，避免把数据库或二进制存储直接打包。

#### 变化

- 添加 Project 级有界 evaluation dataset 与不可变 revision；单模型执行为每个 case 创建普通 Structured
  Run/Attempt，冻结 dataset/Experiment/model 快照，Expected JSON 不进入 provider prompt。
- 增加逐 case 精确 JSON 判定、失败可见性、Run/Attempt/cost 链接、aggregate counts 和只重排尚未开始 case 的 Resume。
- 对 30 分钟 stale case 显示失败且不自动重放；结构化 Attempt、Artifact、Run 终态现在由同一 Run 锁定事务完成，
  避免 recovery 与迟到 response 产生互相矛盾的成功记录。
- 增加每 Run reproduction JSON 下载；包括冻结上下文、版本、Attempt、脱敏工具/事件元数据和文本 Artifact，
  清理敏感字段、常见 credential/token 表达与本机用户路径，跳过二进制内容。
- Run inspector 显示分享审阅提示；Specs 继续留在外部目录并由 `/specs/` ignore 规则排除。

#### 验证证据

- M7 定向测试覆盖 immutable snapshot、exact match/mismatch、safe resume、stale recovery、晚到结构化响应的
  fencing、case revision update、Project deletion 和页面提交；使用 fake RubyLLM response。
- M8 导出测试注入 snapshot、Attempt、tool、event、Artifact 中的 key/token/path sentinel，检查安全 prompt
  保留、秘密替换、二进制省略和下载响应。
- M7/M8 定向测试：15 runs、118 assertions、0 failures、0 errors、0 skips；没有发起真实 provider 请求。
- 全量 Rails 回归：199 runs、1,330 assertions、0 failures、0 errors、2 skips。
- RuboCop：203 files inspected、0 offenses；Zeitwerk `All is good!`；`git diff --check` clean。
- `RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 bin/rails assets:precompile` 完成。
- Docker build、live provider acceptance、浏览器视觉验收和远端 CI 未在本轮验证。

#### 尚未证明什么

- M7 仍为 `PARTIAL`：只有一个 structured-output model 与精确 JSON evaluator；multi-model、batch、semantic judge
  和 live provider acceptance 仍未完成。
- M8 仍为 `PARTIAL`：通用脱敏无法识别所有自定义秘密或个人数据，分享前仍需人工检查；upstream-gap workflow
  和 deployment readiness 未完成。

## 2026-09-20 — M6 speech 首片与本地发布边界修正

### 为什么做

M6 需要先从一个已有回复的可检查媒体产物开始。审查同时发现完成/取消竞态、worker
崩溃后长期停留 `running` 的风险，以及音频 usage 不能按普通文本 token 价格计算。

### 变化

- 添加 speech-capability 目录和 assistant 回复入口；异步 Speech Run 冻结原文、来源、
  provider/model，RubyLLM 返回的音频保存为带 provenance metadata 的 Active Storage Artifact。
- Run inspector 提供音频播放器与下载；RubyLLM speech instrumentation 关联到对应 Run/Attempt。
- 用 RubyLLM `audio_tokens` 类别估算语音费用；缺少价格或 usage 时保留 unknown。
- 音频 Artifact、Attempt 和成功 Run 在 Run 锁内的同一事务里完成，取消先提交时丢弃晚到结果。
- 加入每分钟 stale-speech 检查：超过 30 分钟仍 running 的任务标为 `worker_interrupted`，保留失败
  Attempt，并提示新建 Run 重试；不重放可能已被 provider 接收的请求。
- 单容器 Docker 示例启动 Solid Queue supervisor；CI 增加 Zeitwerk 检查，CONTRIBUTING 的验证说明对齐。
- `/specs/` 整体加入 `.gitignore`；Specs 留在外部工作目录，公开仓库不分发它。

### 验证证据

- Speech focused tests：17 runs、92 assertions、0 failures、0 errors、0 skips；使用 fake RubyLLM
  response，没有调用真实 provider。
- 语音成功/失败、来源快照、播放/下载、LifecycleEvent、取消竞态、30 分钟 recovery 和 audio token
  费用分类均有本地自动化覆盖。
- Docker build、真实 provider speech、浏览器视觉验收与远端 CI 尚未验证。
- `SOLID_QUEUE_IN_PUMA=1` 和 CI Zeitwerk 的配置静态检查待随完整回归复核；公开分发 license 仍需项目
  所有者选定。

### 尚未证明什么

- M6 仍为 `PARTIAL`：只实现 speech；image、video、transcription 和真实 provider 兼容性仍待完成。
- 30 分钟是应用恢复边界，不保证 provider 会停止已接受的请求；新的 Run 可能再次产生费用。
- M5 live provider/Agent browser 验收仍开放，但不阻止继续做本地 M6–M8 切片。

## 2026-09-20 — M5 Solid Queue worker 崩溃与副作用重放演练

### 为什么做

确定性 Job 测试不能证明真实 Solid Queue worker 被杀后会如何恢复，也不能覆盖
本地工具效果已提交、RubyLLM tool result 尚未写入时的崩溃窗口。

### 变化

- 将测试环境的 Solid Queue 放到独立 SQLite 数据库，避免混淆应用数据与队列进程状态。
- 新增真实 fork supervisor/dispatcher/worker 的 provider-free 集成演练；worker 在
  `save_run_note` Artifact 提交后、ToolCall result 持久化前被 SIGKILL，replacement
  worker 通过 outbox 与过期 Run lease 重放该步骤。
- 新增 provider-free 并发取消演练：真实 `AgentRunJob` 与 RubyLLM Chat 在 completion
  边界暂停时由另一线程取消 Run，放行迟到响应后确认它没有写入 assistant transcript。
- Run 删除现在先移除 Artifact、AgentRunDelivery 和 ToolInvocation，再移除被前几者引用的
  Attempt，修正 Project 删除时的外键依赖顺序。
- Docker 单用户示例改为挂载 named volume，文档说明 SQLite、队列状态和上传文件的保留与删除边界。

### 验证证据

- `PARALLEL_WORKERS=1 bin/rails test test/integration/agent_run_worker_replay_test.rb`：
  1 run、17 assertions、0 failures、0 errors。
- `PARALLEL_WORKERS=1 bin/rails test test/integration/agent_run_cancellation_race_test.rb`：
  1 run、13 assertions、0 failures、0 errors。
- RuboCop：新增集成测试和 Run model 3 个 Ruby 文件无 offenses；`git diff --check` 通过。
- 测试结束后 `SolidQueue::Process.count` 为 0，supervisor 与 worker 均已退出。
- 故障重放前后 Artifact id 相同、该 tool-call id 仅有一个 Artifact，Run 最终成功。

### 尚未证明什么

- M5 仍为 `PARTIAL`：真实 provider web search 与多步 Agent dogfood 仍待验证。
- 本演练使用 provider-free 假 Agent 与本地 `save_run_note`；它证明此工具的已提交 Artifact 重放，不证明外部副作用或已被 provider 接收的请求可撤销。
- 取消演练用假 completion 暂停真实 RubyLLM Chat/Agent 路径，证明迟到响应被本地 Run lease fencing 拦截；它不证明外部 provider 会停止已接受的请求。
- Docker named-volume 用法已写入示例，镜像构建仍未在本机或远端 CI 验证。

## 2026-09-20 — M5 工具副作用重放回归与 provider dogfood 门

### 为什么做

Run lease fencing 之外，还需要证明相同的已持久化工具调用在重放时不会重复创建本地
Artifact。M5 的 provider 搜索/Agent dogfood 也需要有一个可重复的显式入口。

### 变化

- 增加 `save_run_note` 相同 tool-call id 重放测试，确认重试复用原 Artifact。
- 增加 OpenRouter 多步 Agent + hosted search opt-in 测试，并在运行手册中说明发送的
  临时 Project 摘要及潜在搜索费用。
- 记录 M6 文字转语音、M7 immutable evaluation dataset、M8 redacted reproduction export
  作为 M5 gate 之后的首批切片。

### 验证证据

- `PARALLEL_WORKERS=1 bin/rails test test/services/ai/tool_registry_test.rb test/integration/openrouter_live_test.rb`：
  7 runs、19 assertions、0 failures、0 errors、2 skips；provider 测试在默认配置下跳过。
- RuboCop：3 个 Ruby 文件无 offenses；`git diff --check` 通过。
- 一次显式 provider 尝试在 DNS 解析阶段失败；自动审批随后拒绝向 OpenRouter 发送测试 prompt 和
  Project 摘要并承担搜索费用。没有取得 provider 响应或 dogfood 证据。

### 尚未证明什么

- M5 仍为 `PARTIAL`：Solid Queue worker 进程终止/重启、真实 side-effect 崩溃窗口和 provider-backed
  搜索/Agent 路径尚未验收。

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

暂无历史条目校正。新发现与后续验证记录如下；发现历史记录与代码证据不一致时，
在这里追加日期、错误描述、校正依据和受影响文档，而不是无声修改旧条目。

## 2026-09-20 — M6 image、video 与 transcription 本地验收

### 为什么做

新媒体路径已进入 Rails 请求、Solid Queue、Active Storage 和 Run inspector，但没有自动化覆盖。
补齐 fake-provider 路径可以验证本地生命周期，也检查 RubyLLM 2.0.0 的实际返回对象契约。

### 变化

- 新增集成测试覆盖 image、video 与 transcription 的排队、provider/model 传递、Artifacts、usage/cost 状态和 Run inspector。
- 修复 Image Run 对 RubyLLM.paint 返回值的处理；单张结果是 Image 对象，多张结果才可能是数组。
- 修复 image/transcription jobs 查找 Ai::MediaCatalog 时缺失命名空间的问题。

### 验证边界

- bin/rails test test/integration/media_run_flow_test.rb：4 runs、80 assertions、0 failures、0 errors、0 skips。
- RuboCop 覆盖新增测试和两个修复 job：3 files inspected、0 offenses。
- 使用 fake RubyLLM responses；没有调用真实 provider，也没有验证浏览器视觉或 provider 专属 job 恢复。
- M6 仍为 PARTIAL：真实 provider dogfood、video job handle 恢复和标准 video usage/cost 仍待完成。

## 2026-09-20 — M5 Agent 页面与 Run inspector 本地验收

### 为什么做

Agent 执行和恢复已有 job/service 覆盖，但定义创建、启动 Run 与重新打开 inspector 之间缺少一条请求级集成证据。

### 变化

- 新增请求级集成流程，经过 Agent 列表、定义创建、定义页启动 Run、持久化 delivery 和 fake Agent worker。
- 验证两步执行的 Attempt 与 lifecycle timeline、冻结的 model/tool/instructions revision，以及 Run reload 后 citation Artifact 与来源链接仍可见。
- 在 Agent 定义 revision 前进后，确认已经排队的 Run 仍保留原始 revision 和 instructions。

### 验证边界

- bin/rails test test/integration/agent_run_flow_test.rb：1 run、52 assertions、0 failures、0 errors、0 skips。
- 使用 fake Agent 并由 Active Job test adapter 执行；没有调用真实 provider。
- RuboCop 覆盖该集成测试：1 file inspected、0 offenses。
- 这证明 Rails 请求/响应和模板输出；不替代手动浏览器视觉验收。M5 仍待真实 provider dogfood。

## 2026-09-20 — M6 stale media recovery 验收

### 为什么做

图像、转录和视频请求都可能在 provider 已接收任务后中断。恢复策略必须避免自动重放造成重复费用，并继续保留近期运行中的任务。

### 变化与验证

- 新增媒体恢复任务测试，验证超过 30 分钟的 image、transcription 和 video Run 均失败、记录 worker_interrupted 且不自动重排；5 分钟内的 video Run 保持运行。
- 定向结果：1 run、25 assertions、0 failures、0 errors、0 skips；RuboCop 1 file、0 offenses。
- 此测试验证本地恢复状态转换，不证明 provider job handle 可恢复；该能力仍待完成。


## 2026-09-20 — M7 provider Batch 生命周期切片

### 变化

- 新增按模型 `structured_output` 与 `batch` 双 capability 约束的 provider Batch 提交入口；每个 case 仍保留自己的 Run、Attempt 和 Artifact。
- 保存提交意图、provider batch ID 与状态；显式刷新时按 RubyLLM 返回的稳定顺序把结果映射回原始 case。
- 对没有可靠 provider ID 的过期提交标记为 `submission_unknown`，并排除普通 case stale-recovery，避免重复提交；RubyLLM Active Record batch store 中已有精确 chat 映射时可恢复本地关联。
- M6 文档明确 RubyLLM 2.0.0 没有 public `VideoJob` restore API；应用不依赖内部 RubyLLM API 假装支持可恢复。

### 验证边界

- 本次运行了修改 Ruby 文件的 `ruby -c` 语法检查、13 个文件的 RuboCop、schema 与 recurring YAML 语法检查以及 `git diff --check`；尚未为新 Batch 生命周期补 fake-batch 自动化，也没有运行完整测试套件。
- 没有调用真实 provider。模型 capability 来自 RubyLLM 2.0.0 的模型注册表；实际 provider 配置、远程结果和计费行为仍待 dogfood。
- M7 仍为 `PARTIAL`；多模型比较、语义评估和 Batch 自动化证据仍未完成。

## 2026-09-20 — M5.4 审批协议闭合与 M6 媒体存储持久性

### 为什么做

取消等待审批的 Run 后，RubyLLM 持久化的工具调用仍可能没有对应结果，阻断后续对话。Active Storage
使用 `attach(io:)` 时，字节上传可能延迟到数据库提交之后；provider 请求成功后存储失败会让 Run 与媒体 Artifact
状态不一致。转录输入也需要先确认原始音频已经保存，再建立依赖它的 Run。

### 变化

- M5.4 按实际待处理调用清理审批，即使取消发生在 Approval 已持久化、Run 尚未进入
  `waiting_for_approval` 的时间窗内也会保存本地拒绝结果或远程 provider 协议拒绝响应。审批与
  ToolInvocation 进入终态；待审批取消不会留下影响后续 Chat 的取消标记。
- M6 在 Run 成功提交前同步上传生成的 image、video、speech 字节；转录 Run 在创建前同步上传输入音频。
  事务失败时清理未附加 Blob，并每日清理超过 24 小时仍未附加的 Blob。
- 空白转录统一保存为受支持的空 transcript 表示，并保留 `empty_transcript` 标记。

### 验证边界

- M5.4 与 M6 定向回归：22 runs、268 assertions、0 failures、0 errors、0 skips。
- 单进程全量 Rails 测试：230 runs、1,843 assertions、0 failures、0 errors、2 skips；本次变更涉及的 2 个 Ruby 文件通过 RuboCop，无 offenses。
- `bin/rails zeitwerk:check`、recurring YAML 解析和 `git diff --check` 通过。媒体与远程工具协议路径使用 fake RubyLLM
  对象，没有调用真实 provider；video provider-job 恢复、浏览器视觉验收和托管 Docker CI 仍待完成。
## 2026-09-21 — M7 evaluation attachment format precheck

### Why

The attachment allow-list previously trusted the MIME type supplied by a
multipart upload. A client could label arbitrary bytes as PDF, an image, JSON or
CSV, and the invalid file would become part of a permanent dataset revision.

### Changes

- Check each raw upload after the existing per-file, per-case and per-revision
  size/count bounds pass, but before creating the new revision.
- Use the declared MIME to select a format check, falling back to the filename
  extension only when MIME is missing or `application/octet-stream`. Check PDF
  headers, JPEG/PNG signatures, parse JSON and CSV syntax, and require valid
  UTF-8 text without binary control bytes. Restore the upload IO position after
  inspection so Active Storage can consume it normally.
- Keep downloads as `application/octet-stream`. These checks establish basic
  format consistency; they do not fully decode PDFs/images or detect malware or
  polyglot files.

### Verification boundary

- No tests or lint were run for this addition. `ruby -c` passed for the validator
  and dataset model; `git diff --check` passed and no trailing whitespace was
  found in the changed source/docs. No provider requests were made.
