# 页面学习层（How this works）

页面学习层把 Workbench 的功能入口和它的实现证据连起来：使用者仍然在原页面完成
Model Explorer、Chat、Experiment、工具审批或 Knowledge 操作，同时可以打开一个局部
说明面板，看到人类说明、执行步骤、版本、允许展示的源码片段、Rails/RubyLLM 官方资料
和当前能力边界。

## 当前实现

学习主题是版本控制中的静态注册表，位于 `app/services/learning/topic_registry.rb`：

- `model_explorer`：RubyLLM catalog、provider 配置状态、能力筛选与可运行性边界；
- `chat_setup`：Project 如何建立 Chat，以及 provider/model 如何进入第一次 Run；
- `chat_run`：Rails action 如何进入 durable Run/Attempt，再进入 RubyLLM ChatExecutor；
- `tool_approval`：代码定义工具如何经过 allowlist、RubyLLM tool call 和 durable approval；
- `experiment_comparison`：冻结定义、选择结构化模型、每个目标建立独立 Run 并验证 Artifact；
- `run_inspector`：Run/Attempt 生命周期、usage/cost/diagnostics 和安全的本地事件时间线；
- `project_boundary`：从 Projects 列表/新建开始，解释 slug 路由、资源归属、Project 级工具策略和 Run 快照；入口接在 Projects 列表与 Project inspector；
- `knowledge_ingestion`：文本/文件如何经过 extraction、provenance 和 deterministic chunks；
- `knowledge_search`：已就绪来源如何经过 retrieval 和可选 rerank。

页面不让运行时模型生成系统解释，也不提供任意文件浏览器。每个主题只引用显式的
源码路径、行号和 anchor；`Learning::SourceReader` 只允许仓库内的固定顶层目录、限制
片段长度，并要求 anchor 仍然存在。源码行号或 anchor 漂移时，注册表测试会失败。

主要页面入口与解释主题保持一对多而非一按钮一主题：Projects 列表与 Project workspace
共用 Project boundary 说明；Run Inspector 与 Chat/Knowledge 则按创建、执行、检查、摄入和
检索等不同阶段分别链接，避免把相邻但不同的生命周期压成一篇笼统说明。

## 内容合同

一个主题至少要说明：

1. 人正在使用的功能和它的 Rails 入口；
2. 关键应用服务、队列或 RubyLLM 边界的顺序；
3. 使用者可以在数据库/Inspector 中看到的证据；
4. 当前实现明确不能宣称的内容；
5. Rails 与 RubyLLM 的官方背景资料。

版本标签来自当前进程和仓库锁定状态：Rails 版本、RubyLLM 版本、应用版本。它们描述
“这段说明对应哪个实现版本”，不等于部署证明或 provider SLA。

## 维护协议

- 代码路径变更时，同一主题迭代必须更新 registry 的源码引用、说明和测试。
- 新增主题时，先确定稳定的 topic key，再接入实际页面；不要为每个按钮复制一套说明。
- 同一功能存在多个阶段时，按可验证边界拆题：例如 Knowledge ingestion 负责“如何进入”，
  Knowledge search 负责“如何被检索”；Experiment comparison 负责“如何比较”，Run Inspector
  负责“如何检查一次执行”。
- `docs/` 继续记录当前现实，Specs 继续作为原始意图基线；学习层不能静默改写 Specs。
- 源码片段不得包含 credentials、原始 prompt、provider secret、未脱敏 tool payload 或
  任意用户内容。
- 说明中的“Implemented/Partial/Deferred”必须与 `README.md`、`SYSTEM_GUIDE.md`、
  `ARCHITECTURE.md` 和 `IMPLEMENTATION_MAP.md` 的当前边界一致。
