# RubyLLM Workbench 项目内部人类理解文档

这组 `docs/` 是代码仓库内部持续增长的“当前实现层”。它把代码、迁移、测试、
浏览器检查和真实 provider dogfood 压缩成一套人可以快速恢复上下文的系统地图。

它与 `rubyllm-workbench/ai/`、`rubyllm-workbench/supporting/` 下的 Specs 有意是
两套体系，不是同一份文档的两个副本：Specs 是项目的稳定参照和基线，`docs/` 是
项目发展过程中记录实现事实、证据和偏差的增长层。`docs/` 不会因为当前代码已经
变化就反向改写 Specs。

更新时间：2026-09-18
当前实现：M0–M3 核心闭环、M4 本地 Knowledge 检索/rerank/文件来源切片 `IMPLEMENTED`
当前边界：M3 并行 tool-call 应用路径 `IMPLEMENTED`、live provider 兼容性 `PARTIAL`；M4 本地 embedding/检索、兼容 provider rerank、文件上传/本地抽取与 provenance `IMPLEMENTED`（含 OpenRouter dogfood 与本地回归），provider file reference、真实 OCR dogfood、页级 provenance 和更广跨 provider 兼容性仍为 `PARTIAL` 或 `PLANNED`；M5–M8 `PLANNED`

## 两套文档体系的边界

| 体系 | 位置 | 主要意图 | 如何更新 |
| --- | --- | --- | --- |
| Specs 基线 | [`rubyllm-workbench/ai/`](../rubyllm-workbench/ai/)、[`supporting/`](../rubyllm-workbench/supporting/) | 定义原始目标、领域/技术合同、里程碑和验收线 | 只有明确的产品或架构决定才改变；运行时变化不会自动改写它 |
| Specs 的人类基线层 | [`rubyllm-workbench/human/`](../rubyllm-workbench/human/) | 说明 Specs 期望的人类可理解性、功能图和基线状态 | 跟随 Specs 的意图维护；它不是当前代码的运行时镜像 |
| 项目当前实现层 | 本目录 `docs/` | 记录代码仓库现在实际上能做什么、证据是什么、下一步和风险是什么 | 每次主题性实现变更同步增长；必要时记录与 Specs 的偏差 |

当 Specs 与当前实现不一致时，按这个顺序理解：先看 Specs 确认意图，再看代码和
测试确认事实，最后看本目录了解人类可读的当前结论。若实现偏离基线，`docs/` 要
同时写出“基线要求”和“当前行为/风险”，不能为了让状态看起来完成而静默修改
Specs。若确实要改变基线，应在 Specs 体系中单独做出有意的变更，并在本目录的
changelog 中记录两边的关系。

本仓库里的 `rubyllm-workbench/` 是指向外部 Specs checkout 的参照链接。阅读它是
开发前置动作；修改它则属于 Specs 基线变更，不能作为普通实现迭代的副作用。

## 如果只有五分钟

1. 先读 [SYSTEM_GUIDE.md](SYSTEM_GUIDE.md)，了解目标、功能、概念和注意事项。
2. 再看 [ARCHITECTURE.md](ARCHITECTURE.md) 的几张图，理解一次请求如何流动、
   数据如何落库、审批如何暂停和恢复。
3. 需要运行或测试时看 [OPERATIONS.md](OPERATIONS.md)，不要凭记忆配置 provider
   或解读失败状态。
4. 想知道最近发生了什么看 [CHANGELOG.md](CHANGELOG.md)，再用 `git show` 查看
   对应提交的代码证据。

## 文档各自负责什么

| 文档 | 负责的问题 | 权威程度 |
| --- | --- | --- |
| `docs/SYSTEM_GUIDE.md` | 系统是什么、现在能做什么、用户如何理解它 | 当前实现的阅读入口；不覆盖 Specs 基线 |
| `docs/ARCHITECTURE.md` | 模块、数据、事件、时序和状态如何连接 | 当前实现结构图；具体字段以代码/迁移为准 |
| `docs/OPERATIONS.md` | 如何启动、测试、配置 provider、判断证据 | 当前本地操作手册；不包含任何 secret |
| `docs/LEARNING.md` | 页面中的 “How this works” 学习层如何维护、如何绑定代码证据 | 学习层的内容与漂移约束 |
| `docs/CHANGELOG.md` | 每次主题迭代改变了什么、为什么、证据是什么 | 面向人的增长历史，原则上只追加 |
| `IMPLEMENTATION_MAP.md` | Specs 基线到当前代码的实现映射和技术边界 | 当前实现合同与偏差入口 |
| `TODO.md` | 下一步工作、验收门槛和明确延期项 | 当前执行清单 |
| `rubyllm-workbench/ai/` | 产品目标、领域合同、技术合同、里程碑验收 | Specs 意图基线；不替代当前代码事实 |

一句话判断权威来源：**原始意图看 Specs，当前行为看代码/迁移/测试和运行证据，
如何让人读懂看本目录 `docs/`**。当三者出现张力时，记录张力本身，而不是用一层
文档冒充另一层文档。

## 状态与证据标签

状态和证据是两件事，不能混用。当前实现层固定使用这些状态词：

- **`IMPLEMENTED`**：代码路径已经存在，并满足当前 slice 的针对性验收。
- **`PARTIAL`**：只有一部分路径可用，或实现存在但兼容性/验收证据仍不完整。
- **`PLANNED`**：Specs 或路线图提出了目标，但当前代码还没有可宣称的实现。
- **`DEPRECATED`**：仍可能存在，但已不应作为新代码或新流程的推荐路径。
- **`REMOVED`**：历史上存在过，当前代码和入口都不再提供。

证据可以附加在状态后面：

- **`LOCAL_VERIFIED`**：当前工作区运行过测试、浏览器检查或 `zeitwerk:check`。
- **`OPENROUTER_DOGFOOD`**：使用当前本地 credentials/环境做过真实 provider 检查；
  只说明这次本地行为，不说明生产部署或长期稳定性。
- **未宣称的外部结果**：本地测试、dogfood、commit 或健康检查都不等于生产部署、
  公众可用、业务收益、审批通过或 provider SLA。

## 每次迭代的文档维护协议

完成一个主题性代码改动时，按下面的顺序同步：

1. 先回看相关 Specs，确认这次变更是在实现基线，还是在提出新的基线决定。
2. 在 `TODO.md` 更新任务和 gate 记录，并明确 `IMPLEMENTED`、`PARTIAL` 或
   `PLANNED` 的边界。
3. 在 [CHANGELOG.md](CHANGELOG.md) 追加一条：目标、用户可见变化、实现位置、
   验证证据、未完成边界，以及是否与 Specs 基线产生偏差。
4. 如果新增实体、状态、队列或 provider 边界，更新
   [ARCHITECTURE.md](ARCHITECTURE.md) 和 [SYSTEM_GUIDE.md](SYSTEM_GUIDE.md)。
5. 如果启动命令、secret 入口、测试命令或故障解释变化，更新
   [OPERATIONS.md](OPERATIONS.md)。
6. 用代码、测试和浏览器检查重新校准本目录；不要为了让文档“看起来完成”而
   把假设写成事实，也不要把当前现实自动倒灌进 Specs。
7. 文档和代码一起做一个主题提交；不要提交 `config/credentials.yml.enc`，
   除非用户明确要求提交 provider 配置变更。

历史记录原则上只追加。发现旧记录错误时，保留原有日期并追加一条“校正”说明，
不要静默改写过去的证据。

`test/docs/human_system_docs_test.rb` 只做结构性守护：确保内部入口、两套体系的
边界声明、核心文档和关键图表仍然存在并互相可达。它不能判断 prose 是否有洞察，
所以每次功能变化仍需由人校准内容和证据等级。

## 回到项目时的快速问题

如果隔了一段时间再回来，先回答这六个问题：

1. 当前实现到哪个 milestone？下一个明确延期项是什么？
2. 一次用户操作会创建哪些 `Run`、`Attempt` 和 Artifact？
3. 当前 provider 是通过哪条 RubyLLM 边界调用的？
4. 哪些状态代表“还在运行”，哪些状态代表“需要人决定”？
5. 最近一次真实 provider 验证证明了什么，又没有证明什么？
6. 当前代码、测试、部署和用户/业务结果之间，证据边界在哪里？

这六个问题答不出来时，先回到本目录，不要直接从局部代码推断整个系统。
