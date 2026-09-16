# RubyLLM Workbench 系统说明

这是一份面向人的“系统心智模型”。目标不是记录每一行代码，而是让人在
AI agent 持续修改系统之后，仍能快速回答：系统为什么存在、现在有什么、一次
操作如何完成、数据在哪里、哪些能力还不能宣称已经存在。

更新时间：2026-09-16
当前实现：M0–M3 核心闭环
当前代码基线：`05781d6 feat: add tool approvals and inspection`

## 两套文档体系：先确认你正在读哪一种“真相”

- **Specs 基线**：[`rubyllm-workbench/ai/`](../rubyllm-workbench/ai/) 和
  [`rubyllm-workbench/supporting/`](../rubyllm-workbench/supporting/) 定义原始目标、
  合同、约束和验收线；[`rubyllm-workbench/human/`](../rubyllm-workbench/human/) 是
  Specs 对人类可理解性的基线说明。
- **项目 `docs/` 当前现实层**：本目录根据当前代码、数据库、测试、浏览器检查和
  provider dogfood 记录“现在实际上发生什么”。它会随项目增长，不是 Specs 的副本，
  也不能替代代码或测试。

Specs 中的 `PLANNED` 可能仍然是正确的基线状态，而本页可以记录其中某个切片已经
  在代码中 `IMPLEMENTED`。反过来，如果当前实现偏离 Specs，本页必须同时写出基线
  意图和实际偏差；不能通过改写 Specs 来消除差异。

## 一句话理解

RubyLLM Workbench 是一个 local-first 的 Rails 工作台：人在一个 Project 中选择
RubyLLM 能力，发起 Chat 或 Experiment，系统把每次执行保存成可检查的 Run、
Attempt、Message、ToolInvocation、Approval 和 Artifact。

它的核心价值不是“替人自动完成一切”，而是让 AI 能力的调用、延迟、成本、失败、
工具副作用和人的决定都留下可追溯证据。

## 产品目标

### 当前目标

- 把不同 provider/model 的能力放进统一的 RubyLLM 边界中比较和试用。
- 让一次 AI 执行在刷新页面、失败或需要审批后仍然可解释、可恢复。
- 让实验结果和工具副作用成为耐久 Artifact，而不是只存在于一次页面响应里。
- 让人能够看到模型做了什么、系统替它记录了什么、哪里需要人介入。

### 当前不做什么

- 不是已经部署给公众使用的 SaaS，也没有账号、团队、计费或多租户。
- 不是 M5 Agent/Deep Research 平台；Agent、工作流和 provider-hosted/server tools
  仍然延期。
- 不是 M4 知识库/RAG/文档 OCR 系统；这些能力尚未实现。
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
| M3 并行 tool calls | 验证多个并行 tool calls 和更多 provider 差异 | 多调用时序和兼容性证据 | `PARTIAL` · 单调用路径已验证，并行兼容性未验收 |
| M4 | 知识集合、摄取、chunk、embedding、检索、rerank、文档提取 | Knowledge*、引用和来源 Artifact | `PLANNED` |
| M5 | Agent、Durable Research、远程工具和可恢复长任务 | AgentDefinition、AgentRunStep、citation/research Artifact | `PLANNED` |

这里的状态是项目当前实现层的判断；Specs 人类基线中的 `PLANNED` 状态仍保留其
“原始需求尚未被基线承认为已完成”的含义。

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

Run 的 `input_snapshot` 冻结这次执行看到的 prompt、工具 schema 和 approval policy。
之后在 Tool Lab 里切换 enabled，不会回写已经开始的旧 Run。

### Attempt

Attempt 是 Run 内的一次具体 provider/model 请求。重试或 fallback 必须新增 Attempt，
不能把旧的失败请求改写成成功。这样人才能区分“第一次失败”和“第二次重试成功”。

### Experiment / Execution / Artifact

- **Experiment**：可复用、带 revision 的结构化 prompt 和受限 JSON Schema。
- **Execution**：一次按冻结定义运行的比较任务，通常为每个目标模型创建一个独立
  child Run。
- **Artifact**：耐久产物，例如 JSON、文本、报告或未来的引用/媒体；Artifact 不
  取代原始 Run/Attempt，而是和原始证据并存。

### ToolDefinition / ToolInvocation / Approval

- **ToolDefinition**：Project 允许使用的代码注册表条目。现在有
  `project_snapshot`（只读）和 `save_run_note`（需要审批）。
- **ToolInvocation**：模型实际请求的一次工具调用，保存 secret-filtered 参数、
  结果、时长、状态和错误。
- **Approval**：一个需要人的工具调用对应的一次决定。审批记录和 RubyLLM 的会话
  决策同时更新；审批不是普通按钮状态，而是执行历史的一部分。

## 一次 Chat Run 是如何工作的

1. 人在 Chat 输入 prompt，应用调用 `Ai::RunExecutor`。
2. 系统同步 Project 的 registry，并把当前 enabled 工具的 key、schema、描述和
   approval policy 写入新 Run 的 `input_snapshot`。
3. 系统原子创建 Run 和第一个 queued Attempt，然后把 `ChatResponseJob` 放入
   Solid Queue。
4. `Ai::ChatExecutor` 领取 Run；同一 Run 已经 `running` 或已经 terminal 时，
   后来的重复 job 不会再次提交 prompt。
5. ChatExecutor 通过 RubyLLM 配置工具并执行 `ask(prompt)`，流式内容继续写入
   RubyLLM Message，同时 Attempt 记录 usage、latency、cost 和 finish reason。
6. 如果模型请求工具，`Ai::ToolInvocationRecorder` 把 RubyLLM 持久化的调用映射成
   ToolInvocation，并过滤参数中的 key/token/secret/password 等敏感字段。
7. 如果工具需要审批，Run 进入 `waiting_for_approval`，页面刷新后仍能看到待决定
   的调用；这时不会假装 Run 已成功。
8. 人 approve 或 deny 后，`Ai::ApprovalService` 同时写应用 Approval 和 RubyLLM
   会话决定，再排入 continuation job。恢复时使用 `complete`，不会重新追加一条
   相同 user prompt。
9. 没有待审批调用时，Run 进入 `succeeded`；provider/tool 异常则进入 `failed`，
   同时保留安全 diagnostic 和结构上可回答的 tool result。

详细的请求时序见 [ARCHITECTURE.md](ARCHITECTURE.md) 的“带审批的 Chat 时序图”。

## 当前两个工具的含义

| 工具 | 副作用 | 默认审批 | 返回内容 | 人要注意什么 |
| --- | --- | --- | --- | --- |
| `project_snapshot` | 无，只读 | `never` | Project 名称、slug、描述和本地计数 | 计数是本地数据库观察，不代表生产数据 |
| `save_run_note` | 创建一个 `report` Artifact | `always` | 保存状态、Artifact id、note | 它会改变本地数据；必须先审批 |

Tool Lab 只管理代码中已注册的 allowlist 条目。它不是在线执行器，也不能把用户
上传的脚本变成工具。

## 页面如何对应系统

- **左侧 rail**：Project 和全局入口；它回答“我正在看哪个上下文”。
- **主画布**：Chat、Experiment、Tool Lab 或 Run 历史；它回答“我正在操作什么”。
- **右侧 inspector**：状态、usage、cost、attempt、工具和 diagnostic；它回答“这次
  执行究竟发生了什么”。
- **Tool Lab**：查看 registry schema、approval policy 和 enabled 状态；开关只
  影响新 Run。
- **Run inspector**：稳定查看单次证据。即使页面不是当前 Chat，也可以从全局 Runs
  回到同一个执行。

## 最容易误读的地方

### “页面显示成功”不等于“系统已经可靠”

成功只说明这一 Run 在当前环境、当前 provider/model 和当前输入下完成。还要看
Attempt、cost provenance、tool result、approval 以及是否存在 provider failure。

### “本地通过”不等于“外部结果”

测试、浏览器 QA、OpenRouter dogfood、commit 和健康检查是不同证据。它们不能互相
替代，也不能直接推出已经部署、已经被用户使用、已经产生业务收益或已经通过审核。

### “工具调用”不等于“Agent”

M3 只是 Chat 中的 allowlisted Ruby tool + 审批 + 审计。M5 Agent 才会引入保存的
Agent 定义、多步运行、远程/provider-hosted 工具、研究引用和更长的可恢复流程。

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
- 当前没有并行 tool-call 的真实兼容性结论，也没有 M4/M5 的实现证据。

这些是本地、点时的验证，不是生产承诺。

## 回到系统时的阅读顺序

1. 看 [README.md](README.md) 的当前边界和证据标签。
2. 看本页的“当前能力地图”和“最容易误读的地方”。
3. 看 [ARCHITECTURE.md](ARCHITECTURE.md) 中与你当前问题对应的图。
4. 看 [CHANGELOG.md](CHANGELOG.md) 最近一条，确认变更的目标和验证。
5. 最后才跳进具体 service/model；用
   [IMPLEMENTATION_MAP.md](../IMPLEMENTATION_MAP.md) 把概念映射回代码。
