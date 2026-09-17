# 本地操作与证据说明

这份手册解决“怎么运行”和“看到结果后能相信到什么程度”。它不保存任何
provider secret，也不把本地成功包装成部署或业务结果。

本手册属于项目内部 `docs/` 当前现实层。原始目标、合同和验收基线仍在
[`rubyllm-workbench/ai/00_ENTRYPOINT.md`](../rubyllm-workbench/ai/00_ENTRYPOINT.md)
及其 supporting Specs 中；两套文档的状态可以不同。操作命令验证的是当前代码，
不会自动改变 Specs。

更新时间：2026-09-16

## 运行前提

- Ruby `4.0.2`
- Rails `8.1.3.1`
- RubyLLM `2.0.0.rc3`
- SQLite、Tailwind、Vite、Hotwire、Solid Queue
- provider 通过环境变量或 Rails credentials 提供配置

如果终端选中了系统 Ruby，先确认 `ruby -v`；本项目不能用 Ruby 2.6 运行。
不要为了绕过版本问题修改 Gemfile，也不要把 token 放到命令行参数里。

## 启动本地工作台

首次准备：

```sh
bundle install
bin/rails db:prepare
```

开发模式：

```sh
bin/dev
```

若只需要一个 Web 进程，必须绑定回环地址：

```sh
bin/rails server -b 127.0.0.1 -p 3100
```

本地服务只应监听 `127.0.0.1` 或 `::1`。完成一次检查后，停止本次任务启动的
服务、watcher、queue worker 和日志订阅。不要留下一个无人查看的源码预览服务。

## Provider 配置

应用只从 RubyLLM 配置边界读取 provider 设置：

- 环境变量，例如 `OPENROUTER_API_KEY`；或
- `config/credentials.yml.enc` 中的加密 Rails credentials。

推荐的检查顺序：

1. 打开 Model Explorer，看目标 provider/model 是否显示为 configured。
2. 在 Project Chat 选择明确的 provider 和 model，不依赖隐式 fallback。
3. 先用低成本/免费目标做一次小 prompt。
4. 到 Run inspector 查看 provider、Attempt、usage、cost provenance、latency 和
   diagnostic。
5. 只在需要真实 provider 行为时运行 live dogfood；测试默认使用 fake provider。

禁止：

- 在 shell 历史、命令行参数、日志、截图或 commit 中出现 plaintext token。
- 读取 credentials 后把完整配置打印出来。
- 把 provider 当前成功误判为生产可用、稳定 SLA 或用户价值。

## 验证分层

先运行便宜、确定性的检查，再做真实 provider 检查：

```sh
bin/rails test
bin/rails zeitwerk:check
bin/rubocop --cache false
bin/rails assets:precompile
```

受限环境无法启动测试并行 worker 时，可显式使用单进程回归；不设置时仍保持默认
并行行为：

```sh
PARALLEL_WORKERS=1 bin/rails test
```

OpenRouter live structured test 是显式 opt-in：

```sh
OPENROUTER_LIVE_TEST=1 bin/rails test test/integration/openrouter_live_test.rb
```

该命令只表示本次本地 provider dogfood；它可能产生费用、受网络影响，也不应在
没有用户明确意图时反复运行。

## Tool Lab 执行模式

Tool Lab 的默认模式是 `sequential`。只有在 Project 中显式选择 `parallel` 时，新建
Chat Run 才会请求 RubyLLM 的 `calls: :many` 与 `concurrency: :threads`。应用在创建
Run 时检查当前模型是否声明 `parallel_tool_calls`，并检查所有 enabled registry 工具
是否声明 `parallel_safe?`；任一条件不满足，就冻结为 `calls: :one`、串行执行，并把
`fallback_reason` 写入 Run 的 `input_snapshot`。

因此排查一次并行行为要看三层证据：

1. Run 的 Input snapshot：requested/effective mode、capability 和 fallback reason；
2. RubyLLM 的实际 ToolCall 数量与每个 ToolInvocation 的状态、参数、结果和时长；
3. Lifecycle events：每个调用独立的 request/completed `event_key`。

当前 `project_snapshot` 是 parallel-safe；`save_run_note` 会创建 Artifact，被标记为
sequential-only，避免把 SQLite 写入和本地副作用未经专门验证地并行化。此策略并不等于
某个 provider 已经承诺会返回多个调用。

## Knowledge workspace：本地文本 + embedding 检索

从 Project 打开 **Knowledge**，按下面的顺序做一次最小验证：

1. 创建一个 collection；collection 始终属于当前 Project。
2. 粘贴一段有明确来源边界的文本，填写 title，可选填写 source reference。
3. 点击 **Ingest source**。应用会规范化换行和首尾空白，计算 SHA-256，并在事务中
   用确定性的 800-character window / 120-character overlap 生成 chunks。
4. 在 Sources 区域检查 `ready`、chunk 数量和 checksum 前缀；打开 Search evidence，
   输入 query，查看每个结果的 score、matched terms、source title 和
   `char_start`/`char_end`。
5. （可选，需要已配置的 provider）在 Embeddings 区选择一个 embedding model，点
   **Embed collection**。Inspector 会显示 status、model、dimensions、coverage 和
   adapter；失败时显示脱敏后的原因。
6. 用 `semantic` 或 `hybrid` 再查一次。semantic 结果是 provider embedding 上的
   cosine similarity；hybrid 同时展示 cosine 与 lexical 分量。

这个页面是独立的同步产品数据流，不会创建 `Run`/`Attempt`。它只在显式 embed 或
semantic/hybrid 查询时才调用 provider embedding 接口：
`lexical` 是精确 token 的 coverage/frequency 评分，只能回答“哪些已存 chunk 包含
查询词”；`semantic` 只能回答“哪些已存向量与 query 向量方向接近”；两者都不是
rerank 结果或模型生成答案。semantic/hybrid 缺少 model、配置、已存向量或 query
embedding 时，页面会退回 lexical 并写明原因。

当前向量以 Float32 blob 存在 SQLite，由 `sqlite_application_cosine` adapter 在应用侧
算 cosine，只适用于有界语料；换 provider 或 model 前先 clear 或重新 embed，避免把
不同维度的向量混在一起。当前 M4 尚未开放远程 URL 抓取、文件上传、Active Storage
文档处理、OCR 或 rerank；这些能力进入时必须补充各自的 provenance、失败状态和兼容性证据。

## 当前可观测性边界

M3 当前切片已经把应用侧生命周期写入 `LifecycleEvent` 目录，并在 Run inspector 中
展示。当前目录覆盖：

- Run：`created`、`started`、`resumed`、`waiting_for_approval`、`succeeded`、`failed`；
- Attempt：`started`、首个流式输出 `streaming`、`succeeded`、`failed`；
- Tool/Approval/Artifact：请求、完成、审批请求/决定和 Artifact 创建。

事件经 `ActiveSupport::Notifications` 进入 SQLite，使用 `event_key` 做幂等去重，且
payload 只保留 ID、状态、provider/model、时长、错误类别等允许的元数据，不复制 prompt、
工具参数、工具结果或 Artifact 内容。事件持久化失败不会阻断主执行，因此 Run/Attempt
等原始记录仍是主要事实来源。迁移前已存在的 Run 不做历史回填。

这仍不是 provider-native 完整事件流、分布式 tracing、成本监控、导出或 dashboard；
并行策略和多调用审计已有本地 deterministic test 证据，但还没有 live provider 并行
返回的兼容性结论。

## 如何读 Run inspector

按这个顺序看：

1. **Run status**：最终是 succeeded、failed，还是 waiting_for_approval；文档状态
   另使用 `IMPLEMENTED`、`PARTIAL`、`PLANNED`、`DEPRECATED`、`REMOVED`，不要用
   “差不多完成”替代它们。
2. **Operation**：是 `chat` 还是 `structured`。
3. **Attempts**：是否有重试、哪个 provider/model 真正执行、usage 和 cost 是否
   已报告/估算/未知。
4. **Lifecycle events**：状态推进、首个流式输出、工具/审批和 Artifact 的本地
   时间顺序；它是导航索引，不是完整 tracing。
5. **Tools**：工具 key、调用状态、脱敏参数、结果、审批和耗时。
6. **Input snapshot**：这次 Run 实际冻结了哪些 prompt、工具、schema 和 tool execution
   policy；如果 requested mode 与 effective mode 不同，先看 fallback reason。
7. **Result/Diagnostic**：最终输出或安全的失败解释。

一个 succeeded Run 仍可能包含重要的 warning/unknown cost；一个 failed Run 仍然
是有价值的故障证据。不要只看绿色状态徽章。

## 常见故障解释

| 现象 | 优先检查 | 不要直接下的结论 |
| --- | --- | --- |
| Model Explorer 显示 unconfigured | provider credentials/config boundary | 不要假装能运行或偷偷换模型 |
| Run 进入 failed | Run diagnostic、Attempt error、provider/model | 不要只看页面异常，也不要重写失败历史 |
| Run waiting for approval | Chat 的 Tool approvals、Approval status | 不要把等待当成功，也不要重复点击触发多个 continuation |
| 页面刷新后消息仍在 | RubyLLM Message 和 Run inspector | 不要把浏览器 DOM 当唯一数据源 |
| Knowledge 搜不到结果 | source 是否为 `ready`、query token、chunk offsets、embedding coverage | 不要把 lexical 当成 semantic embedding 或 rerank |
| Knowledge embedding 失败 | collection embedding status/error、provider 配置、model capability | 不要把脱敏后的错误当成完整 provider 日志，也不要混合不同 model 的向量 |
| Tool 参数不完整 | ToolInvocation 的 secret filtering | 不要为“调试方便”恢复 secret |
| 390px 出现横向滚动 | 页面实际 `scrollWidth/clientWidth`、长 JSON/table | 不要用截图裁剪掩盖布局问题 |
| live test 失败 | 网络、provider availability、model capability、credentials | 不要把一次网络失败改写成代码永远错误 |

## 安全边界

- 本地工具必须来自 Ruby registry allowlist。
- Tool Lab 的浏览器输入只能切换已存在的定义，不能上传或执行 Ruby。
- 工具参数和结果展示必须过滤明显的 key/token/secret/password/authorization 等
  字段。
- LifecycleEvent payload 使用固定字段白名单；不要为了调试把 prompt、原始参数、结果
  或文件内容加入事件通知。
- provider-hosted/server tools 是远程执行能力，未来如果加入必须单独标注；它们
  不等于本地工具，也不应被隐含为安全。
- Knowledge source 当前只接受用户粘贴的 text；不要把任意 URL、上传文件或 OCR
  输出当成已经存在的来源 provenance。
- embedding 错误摘要、collection 状态和事件只保存脱敏后的文本；不要把 provider
  credential、原始响应体或完整 key 写进数据库或日志。
- 任何新建的长期进程都要记录 PID、端口和停止方式；任务结束时清理。

## 变更后最小检查清单

```text
[ ] 代码/迁移已通过针对性测试
[ ] 全量测试、Zeitwerk、RuboCop 或对应静态检查已运行
[ ] 关键页面在桌面和 390px 检查过
[ ] Run/Attempt/ToolInvocation/Approval/Knowledge 的证据边界没有被改写
[ ] 文档的当前能力、图表和 changelog 已同步
[ ] 未把 credentials、token 或内部敏感数据加入 staged diff
[ ] commit 只包含一个清晰主题
```
