# 面向人的迭代记录

这里记录“系统对人来说发生了什么变化”。它不是逐 commit 的机器日志；每一条
都应该回答：为什么改、用户看到了什么、证据是什么、还不能宣称什么。

原则上只追加，不静默改写历史。代码细节回到对应 commit 和
[IMPLEMENTATION_MAP.md](../IMPLEMENTATION_MAP.md)。

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
