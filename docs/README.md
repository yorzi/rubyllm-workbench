# RubyLLM Workbench 人类理解文档

这组文档是给人阅读的系统地图。它不取代 `rubyllm-workbench/ai/` 下的产品
规格，也不取代代码、测试和 Git 历史；它把这些材料压缩成一个能在几分钟内
恢复上下文的理解层。

更新时间：2026-09-16
当前实现：M0–M3 核心闭环
当前边界：M3 的并行 tool-call 兼容性仍未完成；M4–M8 未进入实现

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
| `docs/SYSTEM_GUIDE.md` | 系统是什么、现在能做什么、用户如何理解它 | 人类阅读入口，内容由代码和规格校准 |
| `docs/ARCHITECTURE.md` | 模块、数据、时序和状态如何连接 | 结构图；具体字段以代码/迁移为准 |
| `docs/OPERATIONS.md` | 如何启动、测试、配置 provider、判断证据 | 本地操作手册；不包含任何 secret |
| `docs/CHANGELOG.md` | 每次主题迭代改变了什么、为什么、证据是什么 | 面向人的增量历史，原则上只追加 |
| `IMPLEMENTATION_MAP.md` | 规格到代码的实现映射和技术边界 | 当前实现合同 |
| `TODO.md` | 下一步工作、验收门槛和明确延期项 | 当前执行清单 |
| `rubyllm-workbench/ai/` | 产品目标、领域合同、技术合同、里程碑验收 | 原始规格，优先级最高 |

## 证据标签

文档中的状态不能混用：

- **已实现**：代码、迁移和测试已经存在。
- **本地已验证**：在当前工作区运行过测试、浏览器检查或 `zeitwerk:check`。
- **OpenRouter dogfood**：使用当前本地 credentials/环境做过真实 provider 检查；
  只说明本地这次行为，不说明生产部署或长期稳定性。
- **未完成**：规格已要求，但代码或验收证据还不足。
- **明确延期**：当前刻意不做，避免跨越里程碑或引入未验证的安全边界。

## 每次迭代的文档维护协议

完成一个主题性代码改动时，按下面的顺序同步：

1. 在 `TODO.md` 更新任务和 gate 记录。
2. 在 [CHANGELOG.md](CHANGELOG.md) 追加一条：目标、用户可见变化、实现位置、
   验证证据、未完成边界。
3. 如果新增实体、状态、队列或 provider 边界，更新
   [ARCHITECTURE.md](ARCHITECTURE.md) 和 [SYSTEM_GUIDE.md](SYSTEM_GUIDE.md)。
4. 如果启动命令、secret 入口、测试命令或故障解释变化，更新
   [OPERATIONS.md](OPERATIONS.md)。
5. 用代码、测试和浏览器检查重新校准文档；不要为了让文档“看起来完成”而
   把假设写成事实。
6. 文档和代码一起做一个主题提交；不要提交 `config/credentials.yml.enc`，
   除非用户明确要求提交 provider 配置变更。

历史记录原则上只追加。发现旧记录错误时，保留原有日期并追加一条“校正”说明，
不要静默改写过去的证据。

`test/docs/human_system_docs_test.rb` 只做结构性守护：确保入口、四份核心文档和
关键图表仍然存在并互相可达。它不能判断 prose 是否有洞察，所以每次功能变化仍需
由人校准内容和证据等级。

## 回到项目时的快速问题

如果隔了一段时间再回来，先回答这六个问题：

1. 当前实现到哪个 milestone？下一个明确延期项是什么？
2. 一次用户操作会创建哪些 `Run`、`Attempt` 和 Artifact？
3. 当前 provider 是通过哪条 RubyLLM 边界调用的？
4. 哪些状态代表“还在运行”，哪些状态代表“需要人决定”？
5. 最近一次真实 provider 验证证明了什么，又没有证明什么？
6. 当前代码、测试、部署和用户/业务结果之间，证据边界在哪里？

这六个问题答不出来时，先回到本目录，不要直接从局部代码推断整个系统。
