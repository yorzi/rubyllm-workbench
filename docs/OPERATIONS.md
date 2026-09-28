# 本地操作与证据说明

这份手册解决“怎么运行”和“看到结果后能相信到什么程度”。它不保存任何
provider secret，也不把本地成功包装成部署或业务结果。

本手册说明当前仓库的本地运行方式与证据边界。命令验证的是当前代码路径；它不能
替代部署、公开可用性或 provider 长期兼容性的证据。

更新时间：2026-09-20

## 运行前提

- Ruby `4.0.2`
- Rails `8.1.4`
- RubyLLM `2.0.0`
- Node.js `24.21.0` (see `.nvmrc`)
- SQLite、Tailwind、Vite、Hotwire、Solid Queue
- provider 通过环境变量或 Rails credentials 提供配置

Gem bundle 包含 Active Storage 图像变体处理器；生成图像变体时还需要系统级
`libvips`。可按平台手动安装：

```sh
# macOS (Homebrew)
brew install vips

# Debian / Ubuntu
sudo apt-get install libvips
```

`bin/setup` 会检查 Ruby 能否加载 `libvips`，缺少时打印提示并继续，不会自动安装系统包。
缺少它不会阻止 Rails 启动；需要图像变体时才必须安装。

如果终端选中了系统 Ruby，先确认 `ruby -v`；本项目不能用 Ruby 2.6 运行。
不要为了绕过版本问题修改 Gemfile，也不要把 token 放到命令行参数里。

## 启动本地工作台

首次准备：

```sh
nvm install
nvm use
bundle install
npm ci
bin/rails db:prepare
```

开发模式：

```sh
bin/dev
```

`Procfile.dev` 会让 Rails 与 Vite 显式监听 `127.0.0.1`；保持这个本地隔离边界，
不要把开发服务改成监听所有网卡。

若只需要一个 Web 进程，必须绑定回环地址：

```sh
bin/rails server -b 127.0.0.1 -p 3100
```

本地服务只应监听 `127.0.0.1` 或 `::1`。完成一次检查后，停止本次任务启动的
服务、watcher、queue worker 和日志订阅。不要留下一个无人查看的源码预览服务。

## Docker 镜像

Dockerfile 会在构建阶段安装 Node.js 并执行 `npm ci`，再预编译 Rails/Vite 资源。
镜像仍是无账号和租户隔离的单用户应用；示例只把端口发布到宿主机回环地址：

```sh
docker volume create rubyllm_workbench_storage
docker run --rm -p 127.0.0.1:8080:80 \
  --mount source=rubyllm_workbench_storage,target=/rails/storage \
  -e SOLID_QUEUE_IN_PUMA=1 --env-file .env.production \
  --name rubyllm_workbench rubyllm_workbench
```

SQLite databases, queue state, and locally stored uploads live under `/rails/storage`.
The named volume keeps them when the container is replaced. Back it up before upgrades;
removing the volume permanently deletes this data.
`SOLID_QUEUE_IN_PUMA=1` starts the Solid Queue supervisor with Puma for this single-container
example. For a multi-container deployment, run `bin/jobs` as a separate process and keep the
same durable storage and queue database configuration available to it.

The Runtime inspector shows `Background jobs` readiness separately from web
availability. In Solid Queue mode it reads process heartbeats using Solid
Queue's configured liveness threshold and checks for a recurring scheduler with
`dispatch_agent_run_deliveries`, a dispatcher, and a worker covering the
`maintenance` queue. It also counts due Agent Run outbox deliveries. A missing
process is actionable evidence that scheduled dispatch/recovery may stall; a
ready state does not prove that a provider is reachable or that an individual
job will succeed. The test adapter is labelled separately because it records
enqueued jobs without executing them. Adapters other than test and Solid Queue
are labelled `Not monitored`.

`.env.production` 必须只保存在本机并包含运行时 `SECRET_KEY_BASE`；它不是构建时使用的
`SECRET_KEY_BASE_DUMMY`。可在本地运行 `bin/rails secret` 生成值，再手动放入 `.env.production`
而不要把它作为命令行参数传递。RubyLLM provider 配置先读环境变量，再读加密 Rails credentials；
如果 credentials 没有 `RAILS_MASTER_KEY`，应用会忽略 credentials fallback，因此 env-only 设置仍可启动。
若 provider 配置存于加密 credentials，则要在 `.env.production` 提供对应的 `RAILS_MASTER_KEY`。
`.env.production` 已被 Git 忽略，不能提交到仓库。公开网络部署需要在受信任边界外提供认证、TLS
和 Host 校验；当前镜像示例本身不提供这些保护。

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

## Live provider dogfood

The live suite in `test/live/provider_dogfood_test.rb` is opt-in and skipped by
default. It needs a configured provider (OpenRouter by default):

```sh
bin/dogfood           # free-model scenarios only
bin/dogfood --paid    # adds hosted web search, transcription and image (a few cents)
```

`bin/dogfood` runs the scenarios serially, prints a Markdown summary table and
appends one JSON line per scenario to `tmp/dogfood/<timestamp>.jsonl` (model ids,
Run ids, tokens and cost only). Override models with `DOGFOOD_*_MODEL`
variables, for example `DOGFOOD_AGENT_MODEL=openai/gpt-5-nano`. Runs happen in the
test database and are rolled back. The suite sends its prompts to the provider,
may cost money, and depends on network and provider availability; run it
deliberately, for example after each RubyLLM upgrade.

## Evaluation datasets

在 Project 的 Evaluations 页面创建数据集，并以 JSON 数组录入 case：每项需要唯一的
`key`、`input` 和 `expected_output`。单 case 上限 64 KB，每个 revision 最多 100 项、总计
1 MB。修改 cases 会创建新的不可变 revision；已有 execution 保留旧 revision。

启动比较时选择一个 runnable structured Experiment 和 2–5 个已配置的 structured-output 模型。
应用会冻结同一 dataset revision、Experiment snapshot 和 model list，为每个模型和每个 case
建立独立的 EvaluationExecution 与普通 Structured Run/Attempt。总请求数为模型数乘以 case 数，
会发送各 case 的 input 和 Experiment prompt，也可能产生 provider 费用；`expected_output` 不会加入
prompt。摘要按模型显示通过、失败/不匹配、未完成数量和成本状态；逐 case 表格中的 Run 链接可检查
原始输入、Attempt、Artifact、usage 与 cost。比较只做 JSON 值的精确匹配，不衡量语义质量。

Provider Batch 仍是单独入口，每次只提交一个同时支持 structured output 和 batch 的模型；
结果映射、未知提交和重试边界按单个 EvaluationExecution 管理，不与跨模型 comparison 合并。

`Resume unstarted cases` 只为仍 queued、Run 尚未开始且所有 Attempt 仍 queued 的 case 入队。
这避免盲目重放已可能到达 provider 的请求。每分钟运行的恢复 job 会把超过 30 分钟仍 running
的 case/Run/Attempt 以 `worker_interrupted` 错误码记录失败，不自动重试；需由操作者检查后显式新建 execution。

## Run reproduction JSON

Run inspector 的 `Download reproduction JSON` 导出一个 Run 的冻结 input/result、版本信息、
Attempts 与 usage/cost/error、脱敏后的工具调用和 LifecycleEvent，以及文本类 Artifact 内容。
Chat Run 另外导出入队时冻结的先前消息，以及由该 Run 写入的 user/assistant/tool 消息；
工具调用参数、原始 provider 内容、引用、reasoning signature 和 cache boundary 随消息保留。
Run 消息以入队时保存的 message ID 水位线和结束水位线界定，因此后续 Run 的消息不会并入旧导出。
敏感字段、URL 用户名/密码、常见 API key/Bearer token 样式和本机用户目录路径会被替换；URL 的 scheme、host 与 path 保留，字段按需裁剪到有界长度。
音频等二进制内容不包含在 JSON 中。

导出 schema v2 还限制总文本为 100,000 字符、单个字符串为 20,000 字符、嵌套
深度为 8、每个嵌套集合为 50 项、每类 Attempt/工具/事件/Artifact 为 100 项。
Artifact 最多扫描 1,000 条，每段 Chat 历史最多保留最近 100 条消息。JSON
格式化结果上限为 512 KiB；截断或省略数量会写入 `truncation.omitted`。若仍超过
总字节上限，下载内容会退化为 Run 标识、状态和明确的省略原因。Markdown issue
草稿另有 768 KiB 上限，超限时只保留标题、类别和 Run id，并说明详细内容已省略。
复现文件因此可能不包含完整输入或运行轨迹。

导出可能包含用户 prompt、模型输出和工具上下文。自动脱敏无法识别所有可能的个人信息、私有业务
数据或自定义秘密格式。Chat 附件字节不包含在导出中；导出记录附件元数据并标记 payload 未包含。
provider 状态、可能变化的 provider 配置和模型非确定性也无法由该 JSON 固定。分享前请先检查 JSON，
并按团队的数据保留要求处理原始 Run。针对 Chat context freeze、drift rejection、队列失败、活动 Run 重复提交和审批续跑边界的 provider-free 回归已覆盖；人工分享前复核仍是必要步骤。


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
7. （可选）上传一个文件来源：文本类文件（txt/md/csv/json/yaml/tsv/log，≤10 MB）在本地
   抽取；PDF 与图片需要已配置的 OCR model，否则会明确失败并在 Sources 显示原因。抽取是
   后台 job，页面刷新后看状态；成功后会生成一个 `ocr_document` provenance Artifact。
8. （可选）选择一个已配置的 rerank model 再查一次。rerank 只重排：结果会显示
   `rank N (was M)` 与 rerank score，而 retrieval score / cosine / lexical 分量保持
   不变。没有已配置 rerank model 时该控件不会出现。

这个页面是独立的同步产品数据流，不会创建 `Run`/`Attempt`。它只在显式 embed 或
semantic/hybrid 查询时才调用 provider embedding 接口：
`lexical` 是精确 token 的 coverage/frequency 评分，只能回答“哪些已存 chunk 包含
查询词”；`semantic` 只能回答“哪些已存向量与 query 向量方向接近”；两者都不是
rerank 结果或模型生成答案。semantic/hybrid 缺少 model、配置、已存向量或 query
embedding 时，页面会退回 lexical 并写明原因。

## M6 媒体 Runs

在 chat 页选择 **Image** 或 **Transcribe**，或在一条已保存的 assistant 回复下选择
**Generate audio Artifact**。目录只展示 RubyLLM 明确标记了相应能力的模型；没有可用模型或
provider 尚未配置时，表单会显示禁用状态。

### 图像生成

输入不超过 8,000 个字符的 prompt，选择 image-generation model 并排队。prompt 会发送到所选
provider。Solid Queue 后台任务请求一张图像；支持的 PNG、JPEG、WebP、GIF 或 AVIF 响应保存为
Active Storage `image` Artifact，并记录 provider、model、MIME type、字节数和 SHA-256。Run
Inspector 展示预览和下载。若任务中断超过 30 分钟，recurring scheduler 会将 Run 标为失败，
不自动重放可能已被 provider 接受的请求。

### 音频转录

上传 FLAC、M4A、MP3、MP4、MPEG、OGG、WAV 或 WebM 文件，最大 25 MB。文件先成为 Run 的
`audio` 输入 Artifact，再由 Solid Queue worker 把该 Active Storage Blob 发送给 provider；成功后
transcript 以文本 Artifact 保存，附上 provider、model、语言、时长和输入文件 SHA-256。原始音频
保存在 Active Storage 配置的本地存储中；Run reproduction JSON 不含二进制音频，但会包含
transcript 文本和来源元数据。

### 视频生成

选择 **Video** 后输入不超过 8,000 个字符的 prompt。catalog 仅列出 RubyLLM 标记为 video 输出的
模型；未发现模型时 chat 页会将入口显示为 unavailable，未配置 provider 的选项不可提交。
RubyLLM `animate` 在 Solid Queue worker 中提交并轮询 provider job，因此浏览器请求不会等待渲染。
RubyLLM 发出 `video_job.ruby_llm` 提交事件时，Run 时间线会保存字符串形式的 provider job ID
并标为 `submitted`，供部署者向 provider 排查已提交任务。复现导出会脱敏这个 ID。该记录不支持
恢复 RubyLLM 的轮询对象；worker 中断后 Run 仍按不自动重放策略处理。
支持的 MP4、QuickTime 或 WebM 响应保存为 Active Storage `video` Artifact，并记录 provider、model、
时长、MIME type、大小和 SHA-256。RubyLLM 2.0.0 的 `Video` 结果没有标准化 usage/cost 字段，
因此 Attempt 的费用标为 unknown；不会从 provider-specific raw response 推算金额。

### 语音生成

在一条已经保存的 assistant 回复下选择 **Generate audio Artifact**，挑选目录中声明
`speech_generation` 且 provider 已配置的 model，再提交后台 Run。Run snapshot 会冻结回复
正文、来源 message id、provider/model；正文会发送到所选 provider。任务需由 Solid Queue
worker 执行。成功后 Run inspector 展示播放器、下载链接、Attempt 的 usage/cost 状态，以及
Artifact 中的格式、MIME、字节数和 SHA-256。音频字节保存在 Active Storage 配置的本地磁盘；
备份与恢复它们时要连同 `/rails/storage` 一起处理。

RubyLLM 的 speech 和 transcription 结果按 `audio_tokens` 价格类别估算；image 按 `images`
类别处理。provider 未报告 usage、或 registry 没有对应价格时，费用显示为 unknown。还没有
实时 provider dogfood，所以具体 model 的 voice、格式、图像/视频输出与费用需要部署者自行验证。
RubyLLM registry 未声明的媒体能力不会被这些表单启用。

每分钟运行的 recurring scheduler 会检查超过 30 分钟仍处于 `queued` 或 `running` 的 speech、image、video 和
transcription Run。未被 worker claim 的 queued Run 会标为 `worker_not_started`：此时没有发出 provider 请求；
运行中的 Run 会标为 `worker_interrupted`，因为 provider 可能已接受请求。两种状态都不会自动重放，用户需要
显式新建 Run。拒绝入队的 Active Job 会立即关闭为失败。scheduler 停止时，stale recovery 不会运行。
每天凌晨 4 点的 recurring job 会清理创建超过 24 小时且仍未附加到记录的 Active Storage Blob，以回收进程在
上传成功、数据库关联提交前停止时留下的文件。该清理同样要求 Solid Queue recurring scheduler 持续运行。

### 可选：开启 sqlite-vector 扩展 adapter

默认 adapter（`sqlite_application_cosine`）不需要任何外部依赖。想让 SQLite 扩展来做
扫描时，显式提供二进制并声明 adapter：

```sh
# 二进制不入库：自行下载对应平台的 release 并放置，或直接指路径
SQLITE_VECTOR_PATH=/path/to/vector.dylib \
KNOWLEDGE_VECTOR_ADAPTER=sqlite_vector_extension \
bin/rails server -b 127.0.0.1 -p 3100
```

开启后页面会显示 effective adapter。二进制缺失或加载失败时会回退到默认 adapter，并在
Inspector 写明原因；这不是错误，也不是降级为近似搜索——spike 只用
`vector_full_scan` 的 exact cosine，不涉及 INT8/TurboQuant 量化。扩展会按需维护
`knowledge_vector_index_<dimension>` 派生索引表（可删除重建，不在 schema.rb 中）。

当前向量以 Float32 blob 存在 SQLite，默认由 `sqlite_application_cosine` adapter 在应用侧
算 cosine，只适用于有界语料；换 provider 或 model 前先 clear 或重新 embed，避免把
不同维度的向量混在一起。当前 M4 尚未开放远程 URL 抓取、provider file reference
lifecycle、真实 OCR dogfood 或页级 provenance；文件上传、Active Storage 文档处理
和 rerank 已有本地实现，但 provider 兼容性与真实 OCR 证据仍需单独验证。

## 当前可观测性边界

M3 当前切片已经把应用侧生命周期写入 `LifecycleEvent` 目录，并在 Run inspector 中
展示。当前目录覆盖：

- Run：`created`、`started`、`resumed`、`waiting_for_approval`、`succeeded`、`failed`；
- Attempt：`started`、首个流式输出 `streaming`、`succeeded`、`failed`；
- Tool/Approval/Artifact：请求、完成、审批请求/决定和 Artifact 创建。
- Provider：speech、image、transcription 和 video 分别以 `ai.provider.speech`、
  `ai.provider.image`、`ai.provider.transcription`、`ai.provider.video` 记录 model/provider、
  可用的 usage/费用和白名单 metadata，不复制合成文本、prompt 或媒体内容。

事件经 `ActiveSupport::Notifications` 进入 SQLite，使用 `event_key` 做幂等去重，且
payload 只保留 ID、状态、provider/model、时长、错误类别等允许的元数据，不复制 prompt、
工具参数、工具结果或 Artifact 内容。事件持久化失败不会阻断主执行，因此 Run/Attempt
等原始记录仍是主要事实来源。迁移前已存在的 Run 不做历史回填。

这仍不是 provider-native 完整事件流、分布式 tracing、成本监控或 dashboard；
并行策略和多调用审计已有本地 deterministic test 证据，但还没有 live provider 并行
返回的兼容性结论。

## 如何读 Run inspector

按这个顺序看：

1. **Run status**：最终是 succeeded、failed，还是 waiting_for_approval；文档状态
   另使用 `IMPLEMENTED`、`PARTIAL`、`PLANNED`、`DEPRECATED`、`REMOVED`，不要用
   “差不多完成”替代它们。
2. **Operation**：是 `chat`、`structured`、`speech`、`image`、`video` 还是 `transcription`。
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
| Knowledge 搜不到结果 | source 是否为 `ready`、query token、chunk offsets、embedding coverage、抽取状态 | 不要把 lexical 当成 semantic embedding 或 rerank |
| 文件抽取失败 | item 的 extraction status/error、文件类型是否在允许列表、OCR model 是否已配置 | 不要把“没有 OCR model”当成文件已入库，也不要绕过 Active Storage 直接读磁盘 |
| Knowledge embedding 失败 | collection embedding status/error、provider 配置、model capability | 不要把脱敏后的错误当成完整 provider 日志，也不要混合不同 model 的向量 |
| Rerank 没有生效 | 页面 “Rerank was not applied” 原因、rerank model 是否已配置 | 不要把 rerank 分数当成语义正确性，也不要认为重排会改写检索证据 |
| Run 时间线缺少 `ai.provider.*` | 该 Run 是否由当前进程执行（关联依赖 ExecutionContext）、provider 是否真的被调用 | 不要假设没有 provider 事件就等于没有调用；知识流的 embedding/rerank 本就没有 Run 可挂 |
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
- provider-hosted/server tools 由所选 provider 执行，不等于本地 Ruby 工具，也不受
  Workbench 的 Ruby registry allowlist 约束。当前待审批协议切片只覆盖 RubyLLM 2.0
  Responses/MCP：页面会标明远程执行位置，批准意味着允许 provider 执行该调用。此路径
  有合成记录测试，真实 provider/model 的审批请求与续跑仍未 dogfood；在真实流程验收前，
  不要把这组本地证据当成 provider 兼容性或远程工具安全保证。
- Knowledge source 当前接受用户粘贴的 text 和受应用入口约束的文件上传；文件会经过
  Active Storage 与本地抽取路径，并保存 provenance Artifact。不要把任意 URL、provider
  file reference、未验证的 OCR 输出或页级引用当成已经存在的能力。
- embedding 错误摘要、collection 状态和事件只保存脱敏后的文本；不要把 provider
  credential、原始响应体或完整 key 写进数据库或日志。
- sqlite-vector 二进制是外部可执行代码：只从官方 release 获取，不要入库、不要在 CI 里
  隐式下载未经确认的版本；它默认关闭，只有显式配置才会被加载。
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

## 下载 Run 事件 — 2026-09-27

Run 页面提供 **Download events JSON**。导出该 Run 最新的 100 条本地事件，
按 `occurred_at`、`id` 升序排列，包含事件 ID、关联的 Attempt/Artifact/工具/审批 ID
和经过脱敏的 payload。导出开始时固定事件 ID 上界；后续新增事件需重新下载。

文件不读取 Chat 消息、输入快照或 Artifact 内容；自定义事件 metadata 仍可能包含
私人信息，分享前需要检查。`truncation.omitted` 表示被省略的数据，超过 512 KiB 时
退回 Run 标识和省略原因。下载使用 `private, no-store`。这是本地事件记录，
不代表 provider 完整 tracing，也不补录历史事件。
