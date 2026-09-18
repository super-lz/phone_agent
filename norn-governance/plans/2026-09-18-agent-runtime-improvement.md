# Phone Agent Runtime、Skill 与 MCP 最终改进计划

- 状态：active；开发者已确认推荐方案，正在实施。
- 分支：`main`。
- 基线：`408d632`（Norn v5 治理迁移）；业务实现基线为 `f140cd5`。
- 制定日期：2026-09-18。
- 本次交付：开发者已授权实施；本文保存可跨设备续接的执行状态。提交或推送仍需当时单独授权。
- 权威入口：`norn-governance/spec/main-spec.md`。本文是临时实施导航；完成或取消本轮改进后删除。

## 结果与边界

目标是让用户能用不同说法完成多步骤手机任务，在工具失败、授权、切后台和进程重启后可靠续接，并真正安装和使用符合能力边界的 Skill、连接远端 MCP。

最终方向：保留 Flutter 和已有业务 adapters；以模型理解目标，以明确的工具契约、权限、运行状态和执行回执约束执行。优先修复权限与恢复，再改发现和完成策略，随后补齐扩展生态。不要先建立完整插件平台，也不要将内置工具逐个改写成 Skill。

完成条件：下文验收场景在确定性测试中通过；指定模型和 Android/iOS 的对应真实场景有验收证据。没有执行过的真机、真实 MCP 或模型检查，明确记为未验证。

非目标：Rust 重写、接入 Codex 服务作为后端、多 Agent 平台、插件市场、云端运行时、后台长期自主任务、任意本机 shell、stdio MCP、完整 Office 编辑器。多 Agent、通用 Code Mode 和高级调度只作为后续方向，不为它们提前建框架。

## 已验证基线

本次核对了完整主规格、下列有效代码、相关测试，以及本地 Codex 源码快照。制定前工作树干净。代码阅读可以说明机制与缺口，不能代替模型或设备验收。

| 范围 | 当前实现事实 | 直接影响 |
|---|---|---|
| 工具选择 | `lib/application/agent/tool_router.dart#AgentToolRouter.route` 先运行确定性规则；命中后跳过模型；模型返回后仍叠加规则，产出 `required_tool_names` | 描述路由已经存在，但关键词仍有优先决策权，不能把此前提交理解为已经消除模式匹配 |
| 结束与正文过滤 | `lib/application/agent/agent_loop.dart` 检查必需工具、修正最终回复；completed replay 会打开全局 `finalizeOnly`。`final_response_guard.dart` 通过词语、结构键和句尾猜测正文性质 | 一个重复子动作可能停止其余工作；正常讨论工具或 JSON 的回答也可能被误判 |
| 预算和去重 | `agent_loop_budget.dart` 的默认预算为 null；`agent_action_ledger.dart#AgentActionLedger` 有 call ID、参数指纹和 receipt，但每次 run 新建 | 保留自然结束、可选熔断和已有去重，不重复开发；补跨重启恢复和动作边界 |
| 恢复 | `lib/domain/workbench/pending_agent_run.dart` 保存原始请求与运行前历史；`WorkbenchController._resumePendingAgentRunIfNeeded` 重新调用 `_runConfiguredModel` | 缺少可恢复的运行中协议历史、动作和工具执行检查点 |
| 权限 | `CapabilityRuntime._permissionBlockedResult` 找不到定义时放行；`_invokeSkill` 的子调用使用 `skipPermissionCheck: true`，并通过全局单例回调传入上下文 | 动态工具和 Skill 嵌套调用未形成统一权限闭环；需要处理跨 run/Workspace 回调串用 |
| 工具事实来源 | schema、名称映射、handler 分派、`tool_prompt_registry.dart` 和 `CapabilityDefinition` 分散维护；`defaultReplayPolicyForCapability` 根据名称片段推断是否可重复 | 新增工具需要同步多处，名称相似不代表读写语义相同 |
| Skill | `CapabilityRuntime._installSkill` 检查目录中的 SKILL.md，读取根 index.js；拒绝 ZIP/Git；`_invokeSkill` 要求脚本，未形成 Skill 正文加载链路 | 目前不能称为标准 Skill 的自由安装使用；安装与脚本执行被错误耦合 |
| MCP | `mcp_manager.dart` 用相同 POST JSON 路径处理 transport，固定请求 ID，按裸工具名找首个 session；`toolDefinitions` 能合入动态工具，但 run 开始时选定工具集合 | SSE、会话协议、错误类型、命名冲突和运行中发现需补齐 |
| 扩展持久化 | store 已有 Skill/MCP 的保存、加载接口；controller 已有启动重连。但安装/连接结果写回列表和 store 的专门逻辑位于批准工具处理路径 | 不能说完全没有持久化；需要统一普通执行与批准执行的生命周期 |
| 上下文 | `conversation_context_builder.dart` 已能压缩历史；`context_budget.dart` 已有按模型窗口估算的预算；loop 在初始消息构造时使用它们 | 补每次模型请求前的预算与运行中压缩，不重新建第二套摘要系统 |

本次测试：Flutter 3.38.10 下执行以下现有测试，55 项全部通过。这些测试包含旧行为断言，不能证明目标架构已实现。

```sh
fvm flutter test test/tool_router_test.dart test/agent_action_ledger_test.dart test/agent_loop_budget_test.dart test/final_response_guard_test.dart test/context_budget_test.dart test/conversation_context_builder_test.dart --reporter compact
```

未验证：本轮未运行完整测试集、flutter analyze、真机、真实模型或远端 MCP。未统计真实模型成功率或 token 降幅，不预设提升百分比。

## Codex 对照与取舍

参照 OpenAI Codex 本地源码快照 `b0659c5386`；下面路径相对于该 Codex 仓库。结论只针对所读开源快照，不推断当前桌面产品的全部私有能力。

| Codex 机制与源码入口 | 本项目采用的最小对应方案 |
|---|---|
| `codex-rs/core/src/session/turn_context.rs`、`session/step_context.rs` 区分 turn 和每次采样的工具/配置快照 | 明确 Run、ModelStep、ToolCall 的身份和状态；每次请求固定可执行工具快照 |
| `codex-rs/core/src/tools/registry.rs`、`router.rs`、`orchestrator.rs` 分离注册、分派与执行控制 | 统一 descriptor/registry 与执行入口；沿用现有 adapter，逐组迁移 |
| `codex-rs/core/src/tools/handlers/tool_search.rs` 使用 BM25 检索 deferred tools | 借鉴按需发现；先用能力描述和模型选择，检索规模确有需要再引入搜索索引 |
| `codex-rs/skills/src/parser.rs`、`ext/skills/src/host_prompt.rs`、`fragments.rs` 解析元数据并加载指令正文 | metadata → 正文 → 引用资源逐层加载；Skill 是操作方法，不是另一种 function call 协议 |
| `codex-rs/rmcp-client/src/rmcp_client.rs` 有 Streamable HTTP、session 与认证相关实现 | 采用经过评估的 Dart 协议实现或受限 transport adapter；不复制整个 Rust MCP 子系统 |
| `codex-rs/rollout/src/recorder.rs`、`core/src/session/rollout_reconstruction_tests.rs` 对应运行记录与历史重建 | 用现有 SQLite 保存结构化运行检查点及关键事件，不先建分布式事件平台 |
| `codex-rs/core/src/compact.rs`、`context_manager/history.rs` 支持运行中上下文维护 | 每轮预算检查与成组压缩，保留未完成调用、授权和动作回执 |
| `codex-rs/core/src/tools/parallel.rs` 有工具生命周期和取消控制 | 先实现正确串行与取消；独立只读工具的有界并发作为最后优化 |

Codex 也使用字符串匹配、检索和静态提示规则。应移除的是“关键词直接决定用户意图、强制副作用或宣告整个任务完成”，而不是所有匹配。协议解析、精确 ID、路径与 schema 校验、目录过滤、能力检索都是合理的确定性逻辑。

## 需求与规格决策

Accepted 表示主规格已接受的产品约束，仍不代表本文中的实施已经获准；Proposed 表示会改变或细化持久行为，必须先确认并在同一实施变更中回写主规格。

### R1 — 工具发现服务于当前目标，不以关键词强制动作

- 来源：主规格“多轮对话与工具调用”第 3–4、16–17 条；此前对模式匹配和通用 Agent 的讨论。
- 建议：删除语义关键词 fast path；模型选择工具，工具不足时允许主动发现；路由故障退回受控的能力描述目录，不把候选转成必须执行的动作。
- 验收：否定句、引用、反问、纯解释、短句承接和同义表达不触发错误副作用；初次漏选后同一 run 能发现并调用所需工具；未知工具拒绝执行。
- 规格回写：Proposed D1；调整强制预路由、固定工具集合、确定性语义兜底和按工具名锁定完成条件的条款。

### R2 — 执行证据与任务结束分开

- 来源：主规格“多轮对话与工具调用”第 14–17 条、“当前阶段边界”和“验收标准”的 receipt、replay、产物真实性要求。
- 建议：保留真实执行证据，移除按工具名编排任务的 `required_tool_names`；重复动作返回 receipt 后由模型处理剩余目标。只有合法模型结束或明确运行边界结束 run。
- 验收：动作 A 重复后仍能完成独立动作 B；call ID 不重执行；失败、拒绝、未执行不能被展示成成功产物；JSON/代码讲解不会仅因关键词而重写；长度截断可续写。
- 规格回写：Proposed D2；替换 replay 必须立即进入全局 final 阶段的规则，并限定正文修正策略。保留“不能伪造成功”的业务约束。

### R3 — 所有执行来源共享权限、校验与审计

- 来源：Accepted，主规格“数据与状态语义”“关键不变量”“失败处理”。
- 建议：内置、MCP、Skill 子调用、Web App 均解析为注册工具；执行时验证 schema、Workspace、调用主体、当前权限和授权凭证。无法识别的工具拒绝；已识别但风险信息缺失的外部工具采用保守策略，不能默认低风险。
- 验收：批准 Skill 不自动批准其高风险子工具；伪造/过期/跨参数/跨 Workspace 的批准无效；完全访问仍审计；调用能力不存在时返回结构化错误。
- 规格回写：已有不变量无需改意图；若新增面向用户的授权有效期或审批交互，先确认对应契约。

### R4 — 从检查点恢复，并处理未知副作用结果

- 来源：Accepted 的运行恢复、授权恢复、用户停止及不重复副作用承诺；新增细化为 Proposed D3。
- 建议：保留运行中协议历史和持久 action ledger；执行前记录 intent，完成后记录 receipt。对外部副作用已发出但未收到确认的崩溃窗口，标记 outcome unknown，先查询/对账，有服务端幂等能力则复用同一 key；否则提示用户判断，不盲目重放。
- 验收：在执行前、执行后回执前、回执后各模拟崩溃；已确认完成的动作不再执行；未知结果不伪称成功；批准后续接同一个任务；取消后重启不恢复，迟到结果可审计且不重启任务。
- 规格回写：D3 明确未知结果与恢复策略。不能用本地 ledger 承诺所有外部系统 exactly-once。

### R5 — 长任务上下文和工具生命周期可靠

- 来源：Accepted 的上下文预算、历史压缩、可选预算、取消与流式超时要求。
- 建议：每次采样前计算 system、工具、Skill、历史和输出预留；优先裁剪可重取工具输出，再压缩完整已完成片段；传输、执行、等待授权、取消具有不同状态。压缩不足时明确失败，不循环压缩。
- 验收：长工具链不会只因初始预算过期而溢出；工具调用和结果不拆散；目标、已授权范围、未完成步骤、资源 ID 与 receipt 可恢复；取消及时恢复输入且阻止后续工具启动。
- 规格回写：在已有语义范围实施；若改变自动中断条件，先确认新增条件。

### R6 — Skill 真正遵循标准，安装与脚本执行解耦

- 来源：Accepted，“Skill 与 MCP”、Skill 验收和兼容性不变量。
- 建议：解析标准 SKILL.md、索引描述、按需加载正文及相对资源；纯指令 Skill 不需要 index.js。内置 Web App 创建/维护、资料报告、Office 工作方法可逐步成为同格式 Skill。目录/ZIP/Git 安装复制到受控目录并持久化，支持启停、删除和明确的升级行为。
- 验收：纯 Markdown Skill 可被显式选择或由模型依据描述选择；未选中正文不全量注入；路径穿越、损坏包和同名冲突有确定结果；重启仍可用；缺 Python/shell/Node 后端时只报告执行不可用，不能伪造脚本已运行。
- 规格回写：核心语义已接受；D4 只确认首批 Git/认证支持边界及不支持时的表现，不宣称任意生态 Skill 都能执行。

### R7 — MCP 的可连接、可发现、可调用与持久化形成闭环

- 来源：Accepted，“Skill 与 MCP”、MCP 失败处理及统一权限要求。
- 建议：HTTP transport 真实区分 Streamable HTTP 与兼容的旧 HTTP+SSE；支持初始化协商、JSON/SSE、唯一请求 ID、session、分页、通知及超时取消；使用 server ID + 原工具名映射避免冲突。配置和凭据分开存储。
- 验收：两个服务器提供同名工具仍准确路由；JSON-RPC error 与 MCP `isError` 均为失败；失效 session 可恢复但不盲重试副作用；连接成功后下一 model step 可发现新工具；重启能恢复配置，单个服务失败不影响内置能力。
- 规格回写：已接受 HTTP/SSE 范围；D4 明确首批认证方式，OAuth 不得在未实现时标成已支持。

### R8 — 一个工具定义源，提示与 UI 有明确职责

- 来源：Accepted 的统一注册、发现、校验、调度及结构化事件要求。
- 建议：descriptor 统一名称、来源、schema、权限、effect/replay、availability 与 handler；schema 是调用契约，Skill 是工作方法，运行时保证权限/状态/结果，UI 只展示真实事件。提示按需组合：稳定规则、当前环境、已选技能和相关工具契约。
- 验收：新增普通工具只需 descriptor/handler，不再改意图关键词表、全局提示大分支或 controller；技术解释中合法出现“工具调用”“Capability”不触发误拦截。
- 规格回写：实现机制留在代码；与 R1/R2 相关的外部行为统一通过 D1/D2 确认。

### R9 — 改进必须可比较、可回退

- 来源：项目验证约束，以及用户要求基于真实代码判断差距。
- 建议：记录任务成功、错误副作用、重复资源、假成功、恢复结果、工具调用数、路由耗时、首 token 时间及 token 估算。用相同任务集与模型配置比较，不把“提示更短”当成成功。
- 验收：确定性安全不变量全部通过；真实模型集与基线逐例比较，关键任务成功率不下降；严重错误副作用和重复已完成动作必须为零；未执行证据清楚列出。
- 规格回写：记录业务验收变化；详细测试方法和实现指标留在测试或活动计划。

### 实施前集中确认的产品决策

| 决策 | 推荐选择 | 对现行规格的改变 |
|---|---|---|
| D1 发现与路由失败 | 路由仅提供候选；支持运行中发现；失败时提供受控能力目录，由模型选择或澄清 | 替换关键词兜底必须强制某类动作、工具只能在 run 开始选定的规则 |
| D2 完成与重复动作 | receipt 防止重复副作用，但不自动结束整个任务；基于结果证据约束完成声明 | 替换指定工具必需成功和 replay 全局 finalize；协议污染检测不按普通词语拦截 |
| D3 不确定执行结果 | 可核验则对账，可幂等则同 key 恢复；均不可时请求用户判断 | 细化原“继续或重试”恢复承诺，公开结果未知状态 |
| D4 首批扩展兼容边界 | Skill 支持系统授权目录/ZIP、公开 HTTPS Git URL 的指定 ref 快照；私有 Git/SSH 明确不可用。MCP 先支持无认证和安全存储的 token/header；完整 OAuth 后续单独验收 | 明确兼容子集，不把“可安装”误称为任意脚本可执行，也不把所有认证机制纳入首批承诺 |

以上都是推荐方案，不是已确认产品事实。尚未回写主规格；讨论稿不得覆盖现行规则。已接受的权限修复与统一注册可独立推进，但整个目标迁移必须先处理 D1–D4。

## 目标结构与迁移原则

```text
Workbench UI / Controller
        │ 用户输入、授权、取消 / 真实运行事件
        ▼
Run coordinator + checkpoint store
        │ 每个 model step 的上下文与工具快照
        ▼
Model → 工具发现 / Skill 正文加载 → Model
        │ 结构化 tool call
        ▼
Tool registry → 输入与权限校验 → action journal → handler
                                                   │
                            native / file / DB / MCP / 受控脚本
                                                   │
Model ← 精简 observation ← 结构化结果与 receipt ←─────┘
UI    ← 工具状态、结果、授权、Artifact 事件
```

- Run 对应一次用户请求；model step 对应一次模型采样；tool call 对应协议调用；action 对应需去重的实际动作。不要把 Workspace、会话、run 和 action 混成一个 ID。
- 描述注册先覆盖现有能力，允许适配旧映射，逐组删除重复源；不一次重写所有业务 handler。
- 副作用类型和 replay 策略由 descriptor 明确声明，不按 `read`、`status` 等名称片段猜测；外部声明只是提示，不能自行扩大权限。
- 批准凭证绑定调用主体、run、工具、参数摘要和 Workspace；拒绝通用 `skipPermissionCheck` 授权。取消只能阻止未来执行，已提交外部副作用不能被伪称撤回。
- ledger 的原始结果和资源 ID 属于恢复事实；模型摘要不能代替它们。参数 hash 只用于索引，匹配还需核对规范化参数和作用域。
- 单次请求中的“创建两条相同提醒”等显式重复意图需要独立 action；同一 call ID 的协议重放始终返回同一执行事实，不能让模型任意传 `_agentActionId` 绕过去重。
- 保留现有 MessageBlock UI；新增运行事件先适配它，不另建一套聊天界面。controller 逐步减少执行和持久化特判。
- Skill 不代替 `file_read_app_file`、`web_search`、`project_create_web_app`、权限校验或状态机。按需加载的方法可以教模型如何组合这些工具。
- `SkillSandbox` 不视为通用安全执行后端；现有 JS 桥接先做权限与隔离修复，再决定保留为明确支持的受控 JS adapter。不要要求标准 Skill 自带本项目私有入口。

## 实施步骤

所有新文件名是建议新增目标，尚不存在；下列现有入口已核对。测试命令中新增测试需在对应步骤创建后执行。

### S0 [completed] — 建立可复查基线

- 需求：R9。
- 目标：主规格、上述有效调用链、现有六组测试、Codex `b0659c5386`。
- 变化：形成差距、需求、产品决策和后续验收范围。
- 依赖：无。
- 验证：六组测试 55 项通过；代码未修改。真实模型、设备和扩展协议仍未验证。

### S1 [completed] — 确认 D1–D4 并锁定回归任务集

- 需求：R1、R2、R4、R6、R7、R9。
- 目标：`norn-governance/spec/main-spec.md` 的“多轮对话与工具调用”“Skill 与 MCP”“当前阶段边界”“验收标准”“失败处理”；`test/tool_router_test.dart`、`test/final_response_guard_test.dart`、`test/agent_action_ledger_test.dart`。
- 变化：开发者已确认推荐方案；D1–D4 已回写主规格。旧测试中依赖 `required_tool_names`、关键词 fast path 或 replay 全局 final 阶段的断言将在后续步骤迁移；保留权限、结果真实性、隔离和自然结束不变量。
- 依赖：开发者确认具体产品决策。确认前可以准备测试输入，不修改产品语义。
- 风险：不能为了让旧测试全绿而保留已决定移除的关键词策略，也不能把旧行为测试直接删除而丢失业务验收。
- 验证：已将 D1–D4 的稳定语义写入“多轮对话与工具调用”“Skill 与 MCP”“当前阶段边界”；后续实现以新增确定性测试和真实模型场景复验，无凭据正文。

### S2 [completed] — 统一工具定义并封闭权限绕过

- 需求：R3、R8。
- 目标：`lib/domain/capabilities/capability.dart`；`lib/application/capabilities/capability_runtime.dart`、`capability_tool_definitions.dart`、`office_tool_definitions.dart`；`lib/data/bootstrap/phone_agent_seed.dart`；`lib/features/web_app_runtime/web_app_capability_bridge.dart`。建议新增 `lib/application/capabilities/tool_registry.dart`。
- 变化：descriptor 管理静态/动态工具与执行元数据；未知工具拒绝；Skill 子调用重新检查权限；替换通用跳过权限开关为绑定具体请求的已批准执行上下文；完整记录内外层调用关系。
- 依赖：现有权限不变量；设计冻结后其他步骤共用 registry。可先修权限，再逐组迁移注册。
- 风险：保持 Web App namespace、系统权限申请及完全访问审计；默认回放策略不可由工具名称或外部声明越权决定。
- 验证：`fvm flutter test test/capability_surface_test.dart test/capability_runtime_test.dart test/app_permission_test.dart test/web_app_runtime_page_test.dart`；新增未知动态工具、Skill 调高风险工具、批准参数变化、两个 Workspace 并发上下文用例，实际副作用应为零。

### S3 [in_progress] — 从 UI controller 中分离运行状态与模型协议历史

- 需求：R4、R5、R8。
- 目标：`lib/application/agent/agent_loop.dart`、`agent_run_state.dart`、`tool_call_accumulator.dart`；`lib/features/workbench/controllers/workbench_controller.dart`；`lib/data/models/openai_compatible_chat_client.dart`。建议新增 `lib/domain/agent/agent_run.dart`、`lib/application/agent/agent_run_coordinator.dart`。
- 变化：明确 run/step/call 身份；区分流式正文、工具参数、执行、等待权限、取消、失败、完成；模型协议历史独立于 UI 展示历史；每次请求持有工具/配置快照。
- 依赖：S2；先保持现有行为，通过 adapter 输出原 MessageBlock。
- 风险：任何流式异常或半截参数都不能进入真实执行；取消后迟到事件不得复活任务；授权等待不能被存成任务完成。
- 验证：`fvm flutter test test/openai_compatible_chat_client_test.dart test/workbench_controller_test.dart`；建议新增 `test/agent_run_coordinator_test.dart` 覆盖中途取消、部分参数、超时、授权等待和后续输入可用性。

进展（2026-09-18）：`PendingAgentRun` 已版本化保存独立的 provider 协议消息、工具 schema 快照、工具索引和 model step；恢复同一未完成采样时直接使用该快照。批准或拒绝后在同一 run 内开启新的 model step，保留动作账本但清空旧协议快照，避免批准前状态覆盖新的 continuation prompt。运行协调器与显式 step 状态机尚未独立成模块。

### S4 [in_progress] — 持久化动作与检查点，按执行事实恢复

- 需求：R2、R3、R4。
- 目标：`agent_action_ledger.dart`、`lib/domain/workbench/pending_agent_run.dart`、`workbench_store.dart`、`lib/data/workbench/sqlite_workbench_store.dart`、`WorkbenchController._resumePendingAgentRunIfNeeded` 及批准处理路径。
- 变化：持久化带版本的 run checkpoint、tool call 状态、授权等待、action intent、receipt 和必要原始结果引用；从执行中状态续接，成功不重执行；结果未知进入 D3 策略；同 run 多目标不因 replay 丢失后续步骤。
- 依赖：S1 D2/D3、S2、S3。
- 风险：数据库写入和外部副作用不具备天然原子性；本地数据库能力尽可能共享事务，外部动作采用幂等/对账。旧 pending 数据缺少 receipt 时不得假设从未执行。
- 验证：`fvm flutter test test/agent_action_ledger_test.dart test/sqlite_workbench_store_test.dart test/workbench_controller_test.dart`；新增崩溃窗口、重启批准、明确重复意图、取消落库、旧 schema 迁移用例；资源计数及调用次数符合预期。

### S5 [pending] — 将关键词路由改为可扩展工具发现

- 需求：R1、R7、R8。
- 目标：`tool_router.dart#AgentToolRouter.route`、`agent_loop.dart` 的工具快照生成处、S2 registry；建议新增 `lib/application/agent/tool_discovery.dart`。
- 变化：先在内部对照运行新旧选择，随后移除 `_withDeterministicFallbackTools` 的语义 fast path；常驻最小发现入口，模型通过描述选取真实 schema；发现结果只在下一 model step 生效；新增/撤销工具可刷新版本。
- 依赖：S1 D1、S2、S3。
- 风险：发现不等于授权；执行仍重新校验。简单聊天控制额外 token/延迟；不引入“检索没命中就永远不能用工具”的新封锁。
- 验证：`fvm flutter test test/tool_router_test.dart`；新增否定/引用/解释、复合任务、初次漏选、运行中注册和移除工具用例。真实模型任务集比较成功率、误调用及 token，不能只测特定中文关键词。

### S6 [pending] — 收敛提示与完成判断

- 需求：R2、R8。
- 目标：`agent_loop.dart` 中 required tool 和 finalize 分支；`final_response_guard.dart`；`tool_prompt_registry.dart`；`capability_execution_result.dart`、`capability_result_presentation.dart`；`conversation_context_builder.dart`。
- 变化：不以工具名称或“工具调用”等词语决定任务语义；保留 JSON/schema 与协议结构检测，以 finish reason 和真实错误决定续写/重试。稳定提示只说明能力边界和证据要求，工具细节来自 descriptor，工作方法准备迁往 Skill。
- 依赖：S1 D2、S3–S5。
- 风险：不能简单删掉真实性保护。卡片/链接必须来自真实资源，工具失败要作为 observation 返回；自然语言可信度通过目标场景评估，不能声称程序能证明任意一句回答真实。
- 验证：`fvm flutter test test/final_response_guard_test.dart test/capability_result_presentation_test.dart test/workbench_controller_test.dart`；验证 JSON 教学合法、原始协议污染被处理、未执行不展示成功资源、A replay 后仍能做 B、正常最终回复不无故续写。

### S7 [pending] — 将预算、压缩和取消贯穿每个 model step

- 需求：R4、R5。
- 目标：`context_budget.dart`、`conversation_context_builder.dart`、`agent_loop.dart`、`agent_run_state.dart`、S4 checkpoint 存储。
- 变化：每次请求前重算上下文；按组保留未完成调用和结果，长输出保存引用并提供受控片段读取；压缩结果持久化；取消向模型流和支持取消的 adapter 传播。先串行保证正确性。
- 依赖：S3、S4、S5；Skill/MCP 后续接入相同预算。
- 风险：摘要失败不得丢失原始执行事实；不能将模型窗口估计说成 provider 精确 usage；结果未知按 D3 处理。
- 验证：`fvm flutter test test/context_budget_test.dart test/conversation_context_builder_test.dart test/agent_loop_budget_test.dart test/workbench_controller_test.dart`；长链跨多次压缩、压缩后批准、取消和重启不丢目标及 receipt。

进展（2026-09-18）：每次模型采样前都会按当前协议消息和当时工具 schema 重算预算，超窗立即停止后续采样；运行中协议压缩、长输出引用化和取消传播仍待实现。

### S8 [pending] — 接入标准 Skill 的加载与受控使用

- 需求：R3、R6、R8。
- 目标：`CapabilityRuntime._installSkill/_invokeSkill`、`skill_sandbox.dart`、`AgentSkill`、`tool_prompt_registry.dart`、`web_app_jsbridge_guide.dart`、`pubspec.yaml`；建议新增 `lib/application/skills/` 及 `assets/skills/`。
- 变化：解析 YAML frontmatter 与正文；能力目录展示 metadata，选中才加载正文，引用文件按相对路径读取；保留来源与内容版本。将 Web App 创建/维护、资料报告、Office 方法选取少量代表工作流做内置 Skill；脚本声明所需后端，缺失时明确不可用。
- 依赖：S2、S5–S7。
- 风险：外部 Skill 内容不能覆盖权限或用户授权；相对路径访问不能越出包根；WebView 不自动等同隔离沙箱；本机工具仍可直接调用，不强制先经过 Skill。
- 验证：建议新增 `test/skill_loader_test.dart`、`test/skill_execution_test.dart`；覆盖纯指令无脚本、显式调用、描述发现、引用资源、未知字段、坏 frontmatter、同名、缺执行后端、子调用拒绝及不同 run 隔离。使用真实第三方纯指令 Skill 验收，不只使用自制 fixture。

### S9 [pending] — 补齐 Skill 安装、扩展管理与生命周期持久化

- 需求：R6、R7、R8。
- 目标：`lib/data/files/local_app_file_store.dart`、`lib/domain/workbench/workbench_store.dart`、`lib/data/workbench/sqlite_workbench_store.dart`、`workbench_controller.dart`、`lib/features/workbench/widgets/runtime_panel.dart`；建议新增 `lib/data/skills/skill_package_store.dart`、`lib/application/skills/skill_installer.dart`。
- 变化：通过移动端系统文件授权入口导入目录/ZIP，公开 HTTPS Git URL 按 ref 获取快照，不依赖手机 shell；解包、校验、暂存、原子启用、失败回滚。安装/连接状态写入统一应用服务，普通执行和批准执行共用，UI 只订阅变化；提供查看、启停、卸载入口。
- 依赖：S1 D4、S2、S4、S8；MCP 配置状态沿用此生命周期，但实际连接见 S10。
- 风险：ZIP 路径穿越、符号链接逃逸、超大包、包内多 Skill、同名升级、旧数据迁移都需确定处理；凭据不落普通配置。删除 Skill 不删除已产生的用户文件。
- 验证：建议新增 `test/skill_installer_test.dart`；扩展 SQLite/controller 测试验证失败不半安装、更新可恢复、重启保留、普通全访问执行与批准路径结果一致；Android/iOS 实测选择、导入与重启。

### S10 [pending] — 实现可互操作的远端 MCP 子集

- 需求：R3、R4、R7。
- 目标：`mcp_manager.dart`、`CapabilityRuntime` 的动态调用路径、`McpConnection`、S2 registry、S9 扩展服务；建议新增 `lib/data/mcp/` 的 transport 和独立凭据存储适配。
- 变化：先评估现有 Dart MCP SDK 的协议覆盖、取消、平台和维护状态；选择一个实现并锁版本。若没有合适 SDK，只实现已确认 HTTP/SSE 子集，不自行宣称完整协议兼容。补请求关联、协议版本协商、session、分页、工具变化通知、结构化错误、server namespace、认证与重连；外部副作用复用 S4 策略。
- 依赖：S1 D4、S2–S5、S9 的配置生命周期。
- 风险：`isError` 和 HTTP 200 不等于成功；认证头不得跨重定向泄露；断线恢复不等于重新执行；不支持的版本/认证必须显示可操作错误。
- 验证：建议新增 `test/mcp_transport_test.dart`、`test/mcp_manager_test.dart`；用本地可控服务覆盖 JSON、SSE 分片、分页、401、session 失效、同名工具、撤销工具、超时与取消、`isError`。再分别连接真实 Streamable HTTP 与旧 HTTP/SSE 服务验证，不以 mock 代替互操作验收。

### S11 [pending] — 完成端到端验证并删除过渡实现

- 需求：R1–R9。
- 目标：全部相关测试、真实设备验收、旧路由/提示兼容分支、主规格和本计划。
- 变化：在下表场景通过后切换默认路径并移除旧关键词业务分支、重复 schema/提示源及 controller 特判。若有稳定需求和收益数据，再加入声明为独立只读工具的有界并发；写操作保持顺序或资源锁，不提前做通用调度平台。
- 依赖：S1–S10。
- 风险：保留旧模式只能作为短期内部对照，不能永久维护两套 runtime；回退 UI/路由不能回退已经收紧的权限或破坏新存储。
- 验证：`fvm flutter analyze`、`fvm flutter test`、`git diff --check` 全部通过；完成下方真实验收。无实际证据不得标 completed。持久语义和测试已进入仓库后删除本计划；Git 操作需当时授权。

## 端到端验收场景

| 场景 | 必须观察的结果 |
|---|---|
| “解释如何创建网页，暂时不要创建” | 正常解释，无文件或 Artifact 副作用 |
| 讨论“工具调用”、JSON、Capability，或引用安装指令 | 合法正文不因词语匹配被过滤或自动执行 |
| “查最新资料 → 写报告 → 保存文件”，随后“把它改为表格” | 正确使用来源与已有资源；可发现下一步工具；没有硬编码组合工作流 |
| 创建一个 Web App 后读取日志并修复 | 更新同一项目；保留现有静态测试、版本与隔离保证 |
| 重复 call ID、等价动作 A 重试，但任务还需动作 B | A 不重复执行，B 正常完成；receipt 与资源数量可核对 |
| 明确要求创建两条相同内容的记录 | 两个用户意图对应独立 action，不被参数去重错误合并 |
| 授权等待后重启，再批准或拒绝 | 同 run、同参数、同 Workspace 续接；拒绝不执行；批准不能跨调用复用 |
| 工具执行成功后、receipt 落库前杀进程 | 可对账/幂等的动作安全恢复；不可确认的动作显示未知，不盲目再执行 |
| 模型流、SSE 或脚本等待时停止 | 输入恢复；不再启动后续调用；重启不自动恢复被取消任务 |
| 长任务中间多次压缩 | 保留目标、约束、权限等待、资源引用和已执行动作；不拆散调用与结果 |
| 安装纯指令 Skill 与需要 Python 的 Skill | 前者可按需加载；后者安装状态与执行后端可用性分开，未运行不报告成功 |
| ZIP/Git 导入、卸载、重启及损坏包 | 生命周期一致；失败不污染原安装；来源与版本可查看 |
| 两个 MCP 服务同名工具，连接后立即使用 | namespace 准确；同 run 下一 step 可发现；权限决策和审计可追踪 |
| MCP 工具返回 `isError`、401、断线或不支持版本 | 显示真实失败；保留配置；其他能力可用；不自动重放未知写操作 |
| 跨 Workspace、跨 Web App 或 Skill 子调用越权 | 拒绝且不产生副作用；审计能定位原始主体与子调用 |

性能比较记录相同模型/配置下的任务成功、误调用、重复副作用、假成功、恢复成功、输入 token 估算、首 token 时间、总时长及发现成本。对有随机性的模型测试重复运行并报告样本量，不以单次成功证明通用性。

## 交付批次与回退

1. 基础可靠性：S1–S4。得到统一工具事实、权限和可恢复任务，是后续扩展的前提。
2. 通用执行行为：S5–S7。消除关键词主导、过早结束和运行中上下文溢出。
3. 扩展最小闭环：S8–S10。Skill 加载/安装/使用与 MCP 协议/持久化完成真实验收。
4. 发布验收：S11。删除过渡路径，整理规格与代码证据。

每批独立可审查、可测试，不按文件数或行数判完成。数据库 schema 采用可迁移版本；旧 pending 记录单独兼容，不能静默当成可安全重放。更换路由采用短期内部开关对照；开关不能绕过权限、receipt 或审计。

## 续接检查点

- 已完成：S0、S1、S2；完整主规格和关键源码核对，开发者确认 D1–D4 并已回写主规格。路由已移除关键词 fast path 与 `required_tool_names` 完成门；未知工具拒绝执行；审批绑定 request/run/Workspace/参数 hash；Skill 子调用重新经过权限检查；MCP 动态工具默认高风险且使用 server namespace。最终回复过滤仅识别伪协议与可辨别的原始结构化结果，不再因“工具调用”或“Capability”等普通文本误拦截。
- 进行中：S4；`PendingAgentRun` 保存版本化 action ledger。执行前先写 intent、完成后写 receipt；重启将未完成 intent 与未知旧状态转为 `result_unknown`，并把已有 receipt 作为恢复模型上下文。等待授权保留原 run，重启不自动执行。已覆盖版本往返、旧数据兼容、已完成 action replay、独立后续 action 与未知动作不重试。尚需补齐持久化 model-step 协议历史、对账/幂等 adapter 和崩溃窗口端到端测试。
- 下一步：为 SQLite 记录、恢复和取消补确定性测试，再让每次 model step 重算上下文预算；Skill 已能解析标准 frontmatter、按需加载正文和受控相对资源，安装介质与 MCP transport 仍按后续步骤完成。
- 待决策：Skill 与 MCP SDK/来源实现选择由 S8–S10 的验证决定，不虚构已经选定的依赖。
- 已完成验证：相关路由、回复过滤、账本、恢复记录、权限、Skill 文档、MCP 命名空间、控制器与界面测试通过；命令记录于当前工作会话。
- 待验证：完整静态检查与测试、SQLite 崩溃恢复、真实模型对照、真实 MCP 互操作、Skill ZIP/Git 实际导入、Android/iOS 生命周期与权限。当前没有这些验收完成的证据。
- 续接规则：先检查分支、Git 状态、当前规格和相关代码；基线变化时修订计划，不能用本文覆盖新事实。按实际证据更新步骤状态，最多一个 `in_progress`。
