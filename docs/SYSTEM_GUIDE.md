# RubyLLM Workbench 系统说明

这是一份面向人的“系统心智模型”。目标不是记录每一行代码，而是让人在
AI agent 持续修改系统之后，仍能快速回答：系统为什么存在、现在有什么、一次
操作如何完成、数据在哪里、哪些能力还不能宣称已经存在。

更新时间：2026-09-20
当前实现：M0–M4 已验证切片、M5.1 provider 搜索与引用、M5.2 保存的 Agent 定义与 Run 执行骨架
当前代码基线：RubyLLM 2.0.0 stable；M5.2 的快照、outbox、恢复扫描、租约隔离、取消终态和 step/citation 关联已有确定性测试；完整 worker 执行、进程重启和 provider dogfood 待完成

## 实现状态与证据

本指南描述这个仓库当前实际实现的行为。代码与数据库迁移定义运行时；现有测试、
浏览器检查和 provider dogfood 记录哪些路径经过验证；`TODO.md` 与 `CHANGELOG.md`
记录计划和历史。文档中的状态与证据标签分开使用，避免把计划写成已交付能力。

## 一句话理解

RubyLLM Workbench 是一个 local-first 的 Rails 工作台：人在一个 Project 中选择
RubyLLM 能力，发起 Chat 或 Experiment，或建立一个本地 Knowledge collection，
系统把执行保存成可检查的 Run、Attempt、Message、ToolInvocation、Approval 和
Artifact，并把文本来源保存为可追溯的 KnowledgeItem/KnowledgeChunk。

它的核心价值不是“替人自动完成一切”，而是让 AI 能力的调用、延迟、成本、失败、
工具副作用和人的决定都留下可追溯证据。

## 产品目标

### 当前目标

- 把不同 provider/model 的能力放进统一的 RubyLLM 边界中比较和试用。
- 让一次 AI 执行在刷新页面、失败或需要审批后仍然可解释；长任务通过保存的 transcript 和队列 continuation 恢复。
- 让实验结果和工具副作用成为耐久 Artifact，而不是只存在于一次页面响应里。
- 让人能够看到模型做了什么、系统替它记录了什么、哪里需要人介入。
- 先用本地、可检查的文本证据验证 Knowledge 工作流，再逐步验证 provider embedding、
  rerank 和文档提取的边界；页面中的学习入口应同时解释功能、代码路径和证据边界。

### 当前不做什么

- 不是已经部署给公众使用的 SaaS，也没有账号、团队、计费或多租户。
- 不是完整的 M5 Agent/Deep Research 平台：现在有 Project-owned、带 revision 的 Agent 定义，
  每次 Agent Run 使用独立 Chat 和冻结的定义快照，按 RubyLLM Agent step 工作，并接入审批、引用、
  生命周期事件和取消状态。Rails `ActiveJob::Continuable` 配合带 owner token/generation 的数据库租约，
  在行锁内保护 Chat transcript、usage 和当前本地工具写入；普通迟到 Job 不会接管审批等待状态。工具
  contract 变更会阻止旧 Run 继续，内置笔记 Artifact 按 tool-call id 去重。确定性自动化测试覆盖快照、
  outbox 派发/重试、恢复扫描、租约代次、取消终态和 step/citation 记录；完整 Agent worker 执行、真实
  provider dogfood 或 worker 重启仍未验证。已经被 provider 接受的请求仍可能在中断后产生费用。
  审批已写入主数据库但续跑还未进入独立队列数据库时，仍可能因入队故障而滞留。
- 不是完整的 M4 知识库/RAG/文档 OCR 系统：当前有本地文本 collection、chunk、
  provider embedding、SQLite vector adapter、lexical/semantic/hybrid 证据检索、
  兼容 provider rerank，以及文件上传后的本地抽取和 provenance Artifact；provider
  file reference、真实 OCR dogfood、页级 provenance 和更广的跨 provider 兼容性仍未完成。
- 不接受浏览器上传的任意 Ruby，也不执行任意本地 shell/code。
- 本地测试通过、OpenRouter dogfood 成功、Git commit 存在，都不等于生产部署、
  公众可用、业务结果或 provider 长期稳定。

## 当前能力地图

| 阶段 | 人能做什么 | 系统留下什么 | 当前状态 |
| --- | --- | --- | --- |
| M0 | 浏览项目工作台和空状态 | Project、基础页面、SQLite 记录 | `IMPLEMENTED` · `LOCAL_VERIFIED` |
| M1 | 浏览模型、创建 Chat、发送 prompt、查看 Run 历史 | RubyLLM Message、Run、Attempt、usage、cost、latency、diagnostic | `IMPLEMENTED` · `LOCAL_VERIFIED` + `OPENROUTER_DOGFOOD` |
| M2 | 保存结构化 Experiment，选择多个模型比较并重跑 | 冻结的 Experiment/Execution、独立 child Run、JSON Artifact、schema/provider 区分 | `IMPLEMENTED` · `LOCAL_VERIFIED` + `OPENROUTER_DOGFOOD` |
| M3 核心 | 在 Tool Lab 启用代码定义工具，查看调用，审批或拒绝副作用 | ToolDefinition、ToolInvocation、Approval、工具参数/结果/时长/错误 | `IMPLEMENTED` · `LOCAL_VERIFIED` + `OPENROUTER_DOGFOOD` |
| M3 观测切片 | 在 Run inspector 查看执行时间线 | LifecycleEvent、事件名称、关联记录、脱敏元数据和去重 key | `IMPLEMENTED` · `LOCAL_VERIFIED` |
| M3 并行 tool calls | 通过显式策略验证多个调用的应用侧记录和安全降级 | 冻结的 calls/concurrency 选项、多调用 ToolInvocation 和生命周期事件 | `IMPLEMENTED` · `LOCAL_VERIFIED`；live provider 兼容性仍 `PARTIAL` |
| M4 本地文本基础 | 创建知识集合、摄取文本、chunk、checksum、词法检索和证据查看 | KnowledgeCollection、KnowledgeItem、KnowledgeChunk、来源引用与 offset | `IMPLEMENTED` · `LOCAL_VERIFIED` |
| M4 embedding + 检索 | 选择已配置的 embedding model 入库向量，并用 lexical/semantic/hybrid 查看证据 | KnowledgeEmbedding（model/dimensions/packed vector/checksum）、collection embedding 状态、降级原因 | `IMPLEMENTED` · `LOCAL_VERIFIED` + `OPENROUTER_DOGFOOD` |
| M4 rerank | 对已配置的兼容 rerank model 打开第二阶段重排，查看 pre/post rank | rerank score、pre_rank、未应用原因 | `IMPLEMENTED` · `LOCAL_VERIFIED` + `OPENROUTER_DOGFOOD` |
| M4 文档来源 | 上传文件、本地抽取或 provider OCR、查看 provenance Artifact | `ocr_document` Artifact、extractor、页数、blob/内容 checksum | `IMPLEMENTED` · `LOCAL_VERIFIED`（OCR 路径仅测试证据） |
| M4 完整目标 | provider 文件引用与更细的引用 Artifact | provider file ref lifecycle | `PLANNED` |
| M5.1 | 每次 Chat Run 可选 provider 网页搜索，检查来源与远程工具步骤 | 冻结的 provider tool 快照、`citation_set` Artifact、Run 级工具步骤摘要 | `PARTIAL` · `LOCAL_VERIFIED`；provider dogfood 待完成 |
| M5.2 | 保存 Project Agent 定义，按冻结 revision 启动专属 Run/Chat；记录 step、工具、审批、引用并可取消 | `AgentDefinition`、Run snapshot、执行租约、primary delivery outbox、周期派发/崩溃扫描、专属 Chat、Attempt、ToolInvocation、Approval、Artifact、LifecycleEvent | `PARTIAL` · deterministic boundary tests pass；完整 worker 生命周期、重启演练和 provider dogfood 待完成 |

这里的状态描述本仓库当前实现；路线图中的 `PLANNED` 项表示尚未实现的后续能力。

## 关键概念：不要把它们混成一个“结果”

### Project

Project 是最外层的长期上下文边界。它拥有 Chat、Experiment、ToolDefinition 和
Run。切换 Project 意味着切换资源、历史和工具开关的边界。

### Chat / Message

Chat 是一个使用固定 provider/model 的可持续对话。Message 由 RubyLLM 的 Rails
持久化语义保存；页面刷新时从数据库重建，而不是依赖浏览器内存。

### Run

Run 是一次用户能理解的执行请求，有稳定的 inspector URL 和状态：

`queued → running → waiting_for_approval → succeeded | failed | cancelled`

Run 的 `input_snapshot` 冻结这次执行看到的 prompt、工具 schema、approval policy 和
Tool execution policy，以及本次是否启用了 provider-hosted tools。
之后在 Tool Lab 里切换 enabled，不会回写已经开始的旧 Run。

### Provider-hosted web search

Chat 表单默认不启用网页搜索。勾选后，Run 会把 `web_search` 写入快照并调用
RubyLLM 2.0 的 provider-tool API；搜索词会交给所选 provider 的托管服务。具体模型和
protocol 的支持情况并不统一。RubyLLM 会在 protocol 不提供相应 provider-tool alias
时拒绝请求；具体模型能力没有由 ModelCatalog 验证，模型也可能拒绝请求或不调用搜索。
明确的请求错误会让应用将 Run 记为失败；成功响应本身不能证明发生了搜索，需检查
`server_tool_calls` 和 citations。RubyLLM Message 保留这些数据；应用另把标准化
citations 保存成 `citation_set` Artifact。网页链接只在 HTTP(S) 下可点击。

### Attempt

Attempt 是 Run 内的一次具体 provider/model 请求。重试或 fallback 必须新增 Attempt，
不能把旧的失败请求改写成成功。这样人才能区分“第一次失败”和“第二次重试成功”。

审批 continuation 也会创建一个新的 Attempt；它复用已有 RubyLLM 会话，但不把新的
provider 请求覆盖到原来的 Attempt 上。

### LifecycleEvent

LifecycleEvent 是挂在 Run 上的本地事件目录项，用来回答“状态何时发生、关联了哪条
Attempt/工具/Artifact”。它通过 `ActiveSupport::Notifications` 接收应用事件，使用
固定名称和 `event_key` 去重，只保存允许的元数据；prompt、工具参数、工具结果和
Artifact 内容仍留在各自的原始记录中，不复制进事件 payload。它补充 Run/Attempt 等
事实记录，不替代它们，也不等同于分布式 tracing。

### Tool execution policy

Tool Lab 为 Project 保存一个新 Chat Run 的默认执行模式，默认为 `sequential`。选择
`parallel` 不会直接绕过安全边界：只有当当前模型能力元数据包含
`parallel_tool_calls`，且所有 enabled 工具都声明 `parallel_safe?` 时，Run 才会冻结
`calls: many` 和 `concurrency: threads`。否则 Run 仍使用串行 RubyLLM 选项，并在
`input_snapshot` 中留下 `fallback_reason`。因此“请求了 parallel”与“这次实际并行”是
两个必须分开的事实。

### Experiment / Execution / Artifact

- **Experiment**：可复用、带 revision 的结构化 prompt 和受限 JSON Schema。
- **Execution**：一次按冻结定义运行的比较任务，通常为每个目标模型创建一个独立
  child Run。
- **Artifact**：耐久产物，例如 JSON、文本、报告或未来的引用/媒体；Artifact 不
  取代原始 Run/Attempt，而是和原始证据并存。

### KnowledgeCollection / KnowledgeItem / KnowledgeChunk / KnowledgeEmbedding

- **KnowledgeCollection**：Project 之下的本地知识边界；它不跨 Project 共享来源。
  它同时记录 embedding 状态、model、dimensions、coverage 和最近 embed 时间。
- **KnowledgeItem**：一条规范化后的文本来源，保存 `source_kind`、可选的
  `source_reference`、SHA-256 checksum 和 `pending/ingesting/ready/failed` 状态。
- **KnowledgeChunk**：由 `Ai::Knowledge::Chunker` 生成的确定性字符窗口，保存
  position、`char_start`/`char_end` 和 chunker metadata。
- **文件来源与 provenance**：文件来源先经后台 job 抽取（文本类本地读取，PDF/图片需要
  已配置的 OCR model），抽取结果会写成 `ocr_document` Artifact，记录 extractor、文件名、
  字节数、页数、provider/model 与两个 checksum（附件 blob 与抽取文本），因此任何 chunk
  都能追溯到文件和那次抽取。
- **KnowledgeEmbedding**：一个 chunk 在一个 embedding model 下的向量，保存
  provider、dimensions、packed Float32 vector、content checksum 和 usage metadata。
  同 model 重新 embed 会替换行；不同 model 各自成行，检索只在同一 model 内比较，
  checksum 不匹配的 stale 向量会被跳过。
- **检索模式**：`lexical` 是精确 token 的 coverage/frequency 信号；`semantic` 是
  provider embedding 上的 cosine similarity；`hybrid` 同时保留两个分量。任一模式
  的结果都是证据片段，不是模型答案。
- **vector adapter**：默认在应用侧对 SQLite 里的 Float32 blob 算 cosine；也可以显式
  开启 `sqlite_vector_extension`（外部 sqlite-vector 扩展，需自备二进制）做同样的
  exact cosine 扫描。两者含义一致；扩展不可用时会回退并在页面写明原因。
- **rerank**：可选第二阶段，只对已配置的兼容 rerank model 开放；它只重排，不改变
  retrieval score、cosine、lexical 分量或 chunk 证据，并记录 `pre_rank` 与 rerank
  score。rerank 分数是重排信号，不等于语义正确性。
- **provider 遥测**：除了应用自己的 `ai.*` 事件，RubyLLM 的 `*.ruby_llm` 通知会被
  adapter 映射成 `ai.provider.*` 事件（source 为 `ruby_llm`），两者在 Run inspector 里
  并列但可区分来源。provider 托管的工具调用会被标成 remote。

### ToolDefinition / ToolInvocation / Approval

- **ToolDefinition**：Project 允许使用的代码注册表条目。现在有
  `project_snapshot`（只读）和 `save_run_note`（需要审批）。
- **ToolInvocation**：模型实际请求的一次工具调用，保存 secret-filtered 参数、
  结果、时长、状态和错误。
- **Approval**：一个需要人的工具调用对应的一次决定。审批记录和 RubyLLM 的会话
  决策同时更新；审批不是普通按钮状态，而是执行历史的一部分。

## 一次 Chat Run 是如何工作的

1. 人在 Chat 输入 prompt，应用调用 `Ai::RunExecutor`。
2. 系统同步 Project 的 registry，并把当前 enabled 工具的 key、schema、描述、
   approval policy、Tool execution policy 和 provider tool 选项写入新 Run 的
   `input_snapshot`。
3. 系统原子创建 Run 和第一个 queued Attempt，然后把 `ChatResponseJob` 放入
   Solid Queue。
4. `Ai::ChatExecutor` 领取 Run；同一 Run 已经 `running` 或已经 terminal 时，
   后来的重复 job 不会再次提交 prompt。
5. ChatExecutor 通过 RubyLLM 配置本地工具、快照中的 provider tools 与
   `with_tool_options`，再执行 `ask(prompt)`；流式内容继续写入 RubyLLM Message，
   同时 Attempt 记录 usage、latency、cost 和 finish reason。
6. 如果模型请求一个或多个本地工具，`Ai::ToolInvocationRecorder` 为每个 RubyLLM
   持久化的调用映射成 ToolInvocation，并过滤参数中的 key/token/secret/password 等
   敏感字段。provider-hosted 步骤和引用由 RubyLLM 持久化在 Message；provider 引用
   另外形成 citation Artifact。
7. 如果工具需要审批，Run 进入 `waiting_for_approval`，页面刷新后仍能看到待决定
   的调用；这时不会假装 Run 已成功。
8. 人 approve 或 deny 后，`Ai::ApprovalService` 同时写应用 Approval 和 RubyLLM
   会话决定，再排入 continuation job。恢复时使用 `complete`，不会重新追加一条
   相同 user prompt。
9. 没有待审批调用时，Run 进入 `succeeded`；provider/tool 异常则进入 `failed`，
   同时保留安全 diagnostic 和结构上可回答的 tool result。

详细的请求时序见 [ARCHITECTURE.md](ARCHITECTURE.md) 的“带审批的 Chat 时序图”。

## 当前两个工具的含义

| 工具 | 副作用 | 默认审批 | 并行执行 | 返回内容 / 人要注意什么 |
| --- | --- | --- | --- | --- |
| `project_snapshot` | 无，只读 | `never` | `safe` | Project 名称、slug、描述和本地计数；计数是本地数据库观察，不代表生产数据 |
| `save_run_note` | 创建一个 `report` Artifact | `always` | `sequential only` | 保存状态、Artifact id、note；它会改变本地数据，必须先审批 |

Tool Lab 只管理代码中已注册的 allowlist 条目。它不是在线执行器，也不能把用户
上传的脚本变成工具。

## 页面如何对应系统

- **左侧 rail**：Project 和全局入口；它回答“我正在看哪个上下文”。
- **主画布**：Chat、Experiment、Tool Lab 或 Run 历史；它回答“我正在操作什么”。
- **右侧 inspector**：状态、usage、cost、attempt、工具和 diagnostic；它回答“这次
  执行究竟发生了什么”。
- **Tool Lab**：查看 registry schema、approval policy、并行安全标记和 enabled 状态，
  还可以为新 Chat Run 选择串行/并行默认模式；开关和模式都只影响新 Run。
- **Knowledge workspace**：创建 Project-scoped collection，粘贴 bounded text，
  同步生成可替换的 chunks，选择已配置的 embedding model 入库向量，并按
  `lexical/semantic/hybrid` 查看 score、cosine、lexical 分量、匹配词、来源和字符
  offset。该产品页面不会创建 Chat Run/Attempt，也不会在没有明确 embed 操作时
  偷偷调用 provider；semantic/hybrid 不可用时页面会写明降级原因。
- **Run inspector**：稳定查看单次证据。即使页面不是当前 Chat，也可以从全局 Runs
  回到同一个执行；Lifecycle events 时间线展示状态、流式首字节、工具/审批和
  Artifact 事件的本地顺序。

## 最容易误读的地方

### “页面显示成功”不等于“系统已经可靠”

成功只说明这一 Run 在当前环境、当前 provider/model 和当前输入下完成。还要看
Attempt、cost provenance、tool result、approval 以及是否存在 provider failure。

### “本地通过”不等于“外部结果”

测试、浏览器 QA、OpenRouter dogfood、commit 和健康检查是不同证据。它们不能互相
替代，也不能直接推出已经部署、已经被用户使用、已经产生业务收益或已经通过审核。

### “工具调用”不等于“Agent”

M3 是 Chat 中的 allowlisted Ruby tool + 审批 + 审计。M5.2 增加了版本化定义和专属 Agent Run；
Run 继续作为执行边界，定义和 prompt 快照进入 Run，编辑定义不会改写旧 Run。Agent 会按 step
推进，工具执行与审批仍复用项目 allowlist 和 Run 记录。该路径实现尚未通过自动化执行测试。

### “失败”不等于“历史丢失”

失败的 Run、Attempt、工具调用和 diagnostic 应该保留。修复后重试应产生新的证据，
而不是擦掉旧记录。

## 现在应该相信什么

截至本说明更新时间，最强的本地证据是：

- M1 的 OpenRouter chat Run #6 有持久化流式输出、Attempt metrics 和 cost provenance。
- M2 的 Execution #1 保留了成功 child Run 与 provider failure child Run；Execution
  #2 的两个模型都产出了有效 JSON Artifact。
- M3 的 Run #11 完成了真实 `project_snapshot`；Run #13 从
  `waiting_for_approval` 经批准恢复，完成 `save_run_note` 并生成 report Artifact，
  只保留一个 user message 和两条 assistant message。
- 当前本地回归已覆盖 LifecycleEvent 的顺序、去重、脱敏 payload、审批事件和
  continuation 的新 Attempt；Run inspector 也展示这条时间线。
- 当前本地回归覆盖并行策略的能力门控、side-effect 工具串行降级、冻结的 RubyLLM
  options，以及多个 tool calls 的独立 ToolInvocation/request/completion 事件。
- M5.2 新增测试覆盖冻结快照、primary outbox 入队/重试、过期租约与多审批恢复、generation fencing、
  取消后的终态保护，以及 step/citation Artifact 的 Run 时间线关联。全套 Rails 测试、RuboCop、Zeitwerk、
  Bundler Audit、Brakeman 和生产资源预编译通过。完整 AgentRunJob 执行、真实 Solid Queue 重启和 provider
  dogfood 尚未验证；本地浏览器 system test 受 sandbox 禁止 Selenium 回环 socket 绑定影响，未完成断言。
- 当前本地回归覆盖 Knowledge collection、文本 checksum、确定性 chunk offset、ready
  状态、embedding 记录/provenance、vector adapter、三种检索模式的证据分量和降级
  原因；这只证明 M4 本地文本与 embedding 检索切片。
- 真实 provider dogfood：OpenRouter 免费 embedding model
  `liquid/lfm-2.5-embedding-350m:free` 成功 embed 2 个 chunk（1024 维），语义排序
  把相关段落在 cosine 0.5373 排在 0.2334 之前；只覆盖一个 provider 与一个 model。
- 真实 provider dogfood：OpenRouter 免费 rerank model
  `nvidia/llama-nemotron-rerank-vl-1b-v2:free` 在 3 个 chunk 上给出
  0.6758 / 0.111 / 0.0009；它在一次 lexical 并列（0.7833）时把词面重复但离题的段落
  排在语义正确的段落之前，说明 rerank 分数需要人复核。
- 当前仍没有 live provider 返回多个 parallel tool calls 的兼容性结论，也没有 M4
  OCR 或 M5.1 网页搜索切片的 provider dogfood 证据。

这些是本地、点时的验证，不是生产承诺。

## 回到系统时的阅读顺序

1. 看 [README.md](README.md) 的当前边界和证据标签。
2. 看本页的“当前能力地图”和“最容易误读的地方”。
3. 看 [ARCHITECTURE.md](ARCHITECTURE.md) 中与你当前问题对应的图。
4. 看 [CHANGELOG.md](CHANGELOG.md) 最近一条，确认变更的目标和验证。
5. 最后才跳进具体 service/model；用
   [IMPLEMENTATION_MAP.md](../IMPLEMENTATION_MAP.md) 把概念映射回代码。
