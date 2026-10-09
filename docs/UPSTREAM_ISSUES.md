# RubyLLM / Rails 问题与贡献候选

更新：2026-10-09 · Ruby 4.0.2 · RubyLLM 2.1.0 · Rails 8.1.4

只记录可检查的事实，区分框架缺陷候选、改进建议、项目自身问题和
provider 行为。当前没有已确认的 RubyLLM 或 Rails 自身 bug；没有向
upstream 提交 Issue 或 PR。下面的候选仍需要你进一步求证。

## 待求证

### RLLM-001 — 持久化 usage ledger 是否应该保留成本来源

- 类型：RubyLLM 改进候选，不能定性为 bug。优先级：低。
- 本地证据：2.1.0 的 `lib/ruby_llm/active_record/usage.rb` 在
  `attributes_for` 中存储成本分量和 `total_cost`；`tokens` 还原时不带
  `reported_cost`，`cost` 从已存数字还原。生成的 ledger 表也没有成本
  来源列。Workbench 因此将其标为 `recorded`，无法还原最初的
  provider-reported / estimated 区别。
- 影响：金额可以保留，但重新加载后无法据此证明它来自 provider 账单，
  还是基于当时模型价格的估算。Workbench 的 `Ai::CostNormalizer` 和
  `test/services/ai/cost_normalizer_test.rb` 已明确保留这个边界。
- 尚未验证：upstream 当前 main 是否已改变；框架是否有意只承诺金额
  而不承诺来源；全部成本类型在公开 API 的持久化往返表现。
- 下一步求证：在干净 upstream main 上，用公开 Rails chat/usage API
  和受控 HTTP fixture 分别模拟 provider-reported、estimated、explicit
  zero、unknown 成本，保存并重新加载，比较来源和金额。不需要真实付费。
- 可行改进：若 maintainer 认为来源属于 ledger 合约，保存明确的来源
  或 reported 金额，并覆盖 owner-only usage。旧记录保持 unknown，
  不能根据历史 `total_cost` 猜出来源。先确认设计意图再写迁移和 PR。

## 已排除的候选

### RLLM-002 — `with_thinking(false)` 是否遗漏 OpenRouter disable 参数

静态阅读曾产生疑问，公开 API 复现排除了本地 2.1.0 的这个候选：
`Chat#render` 在启用时返回 `reasoning: { enabled: true }`，关闭时返回
`reasoning: { enabled: false }`。不要据此提交 bug。

```sh
bundle exec ruby script/diagnostics/ruby_llm_openrouter_thinking_disable.rb
```

[复现脚本](../script/diagnostics/ruby_llm_openrouter_thinking_disable.rb)
仅生成 payload，使用无效的离线占位值；不加载 Rails，不请求 provider，
不读写应用数据库。它证明本地 payload 行为，不证明每个 endpoint 支持
关闭 reasoning。真实 Liquid endpoint 明确拒绝关闭 mandatory reasoning，
这是 provider 限制，与 RubyLLM 是否正确编码参数分开判断。

## 本次发现但不应归因给两个 gems 的问题

| 发现 | 归属与处理 |
| --- | --- |
| RubyLLM 异常被 Workbench 记成成功/收到响应 | Workbench 通知适配器未识别 Rails 的 `exception_object` / `exception`。已修复并用真实通知总线的离线抛错回归验证。 |
| embedding 检查/查询忽略选定 provider，部分重建混入旧 provider 向量 | Workbench catalog、查询、覆盖数和候选筛选问题。已修复。不能作为 RubyLLM 缺陷提交。 |
| SQLite native 派生索引只比较数量，未感知向量替换与候选排除 | Workbench adapter 问题。已改为从候选快照重建，在同一事务内扫描。测试使用真实 SQLite 索引维护和 Ruby 扫描替身，实际 native binary 验收仍未完成。 |
| Dots schema-invalid、Apodex provider error、Liquid rate limit | 本次只能确认 provider 响应/可用性限制；不能从失败日志推断 gem 有 bug。完整两模型比较仍待复验。 |
| TTS 验收报告把缺失的 token 数显示为 0 | Workbench 报告使用 `.to_i` 聚合缺失值。已修正为 unknown，并覆盖缺失、部分缺失和明确 0 的离线回归。不是 RubyLLM 用量 bug。 |

Rails：本轮没有发现可独立复现的框架缺陷。后续记录新候选时沿用
编号 `RAILS-001`，补上 Rails/Ruby/数据库/适配器版本和最小复现。

## 新候选最少需要什么

记录发现日期、gem 版本、公开 API 的触发步骤、预期与实际、最小复现
命令或脚本、影响范围、已排除的应用/provider 原因、当前状态和下一步。
状态使用“待求证 / 已在版本中复现 / 已在 upstream main 复现 / 已修复
/ 已排除”。没有复现就保留为候选；不要填造 Issue/PR 链接。求证和
补丁优先离线完成，真实请求与付费验收需要单独选择范围。
