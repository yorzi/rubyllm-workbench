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

OpenRouter live structured test 是显式 opt-in：

```sh
OPENROUTER_LIVE_TEST=1 bin/rails test test/integration/openrouter_live_test.rb
```

该命令只表示本次本地 provider dogfood；它可能产生费用、受网络影响，也不应在
没有用户明确意图时反复运行。

## 当前可观测性边界

M3 已经把工具请求、工具完成和审批请求/决定写入应用记录，并在 Run inspector 中
展示；这些记录是当前本地执行的主要证据。生命周期事件的覆盖仍不完整：`ai.run`、
`ai.attempt` 和 `ai.artifact` 的统一 started/succeeded/failed/created 事件属于
`PLANNED` 的后续观测能力。当前不能把数据库 inspector 误称为已经存在的完整事件
流、分布式 tracing 或成本监控系统。

## 如何读 Run inspector

按这个顺序看：

1. **Run status**：最终是 succeeded、failed，还是 waiting_for_approval；文档状态
   另使用 `IMPLEMENTED`、`PARTIAL`、`PLANNED`、`DEPRECATED`、`REMOVED`，不要用
   “差不多完成”替代它们。
2. **Operation**：是 `chat` 还是 `structured`。
3. **Attempts**：是否有重试、哪个 provider/model 真正执行、usage 和 cost 是否
   已报告/估算/未知。
4. **Tools**：工具 key、调用状态、脱敏参数、结果、审批和耗时。
5. **Input snapshot**：这次 Run 实际冻结了哪些 prompt、工具和 schema。
6. **Result/Diagnostic**：最终输出或安全的失败解释。

一个 succeeded Run 仍可能包含重要的 warning/unknown cost；一个 failed Run 仍然
是有价值的故障证据。不要只看绿色状态徽章。

## 常见故障解释

| 现象 | 优先检查 | 不要直接下的结论 |
| --- | --- | --- |
| Model Explorer 显示 unconfigured | provider credentials/config boundary | 不要假装能运行或偷偷换模型 |
| Run 进入 failed | Run diagnostic、Attempt error、provider/model | 不要只看页面异常，也不要重写失败历史 |
| Run waiting for approval | Chat 的 Tool approvals、Approval status | 不要把等待当成功，也不要重复点击触发多个 continuation |
| 页面刷新后消息仍在 | RubyLLM Message 和 Run inspector | 不要把浏览器 DOM 当唯一数据源 |
| Tool 参数不完整 | ToolInvocation 的 secret filtering | 不要为“调试方便”恢复 secret |
| 390px 出现横向滚动 | 页面实际 `scrollWidth/clientWidth`、长 JSON/table | 不要用截图裁剪掩盖布局问题 |
| live test 失败 | 网络、provider availability、model capability、credentials | 不要把一次网络失败改写成代码永远错误 |

## 安全边界

- 本地工具必须来自 Ruby registry allowlist。
- Tool Lab 的浏览器输入只能切换已存在的定义，不能上传或执行 Ruby。
- 工具参数和结果展示必须过滤明显的 key/token/secret/password/authorization 等
  字段。
- provider-hosted/server tools 是远程执行能力，未来如果加入必须单独标注；它们
  不等于本地工具，也不应被隐含为安全。
- 任何新建的长期进程都要记录 PID、端口和停止方式；任务结束时清理。

## 变更后最小检查清单

```text
[ ] 代码/迁移已通过针对性测试
[ ] 全量测试、Zeitwerk、RuboCop 或对应静态检查已运行
[ ] 关键页面在桌面和 390px 检查过
[ ] Run/Attempt/ToolInvocation/Approval 的证据边界没有被改写
[ ] 文档的当前能力、图表和 changelog 已同步
[ ] 未把 credentials、token 或内部敏感数据加入 staged diff
[ ] commit 只包含一个清晰主题
```
