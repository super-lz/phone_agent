# Phone Agent 第一版本实现规格

本文件是当前项目的主实现规格，记录业务语义，不复述代码实现。填写和维护规则见 `docs/spec/AGENTS.md`。

## 目标

- 真实用户：希望在手机上使用 AI 处理学习、工作、生活和创作任务的个人用户；同时包含愿意接入 MCP、Skill、Web 小应用和手机本地能力的高级用户。
- 真实问题：现有移动端 AI 助手通常停留在聊天、搜索或内容生成层，难以统一调用手机本地能力、用户文件、记忆、Workspace、外部工具和可复用产物。
- 可感知结果：用户可以在移动端通过对话让 AI 搜索、读取文件、理解图片、调用工具、管理记忆、生成 Artifact，并创建能调用手机能力的本地 Web 小应用。
- 达成信号：默认 Workspace 中能完成多轮对话、工具调用、记忆读写、Artifact 创建、Web App 创建和权限审计的最小闭环。

## 背景与约束

- 第一版本定位为移动端多模态 Agent 工作台和手机本地能力基座。
- 产品基础水位应对齐豆包、ChatGPT、Codex、OpenCode、Cline 这类产品的对话和工具能力：多轮对话、Markdown、图片和文件输入、联网搜索、工具轨迹、任务进度、权限请求、可复用产物和外部工具接入。
- Web 小应用不是唯一目标，而是 Artifact 的一种高级形态；它通过 JSBridge 调用受控手机能力，使用户可以用 AI 创建轻量手机应用。
- 第一版本不实现语音输入或输出、不实现远程终端、不建设云端运行时、不做后台长期自主执行、不做插件市场、不允许任意网页默认调用手机能力、不实现 iOS 本机 shell、不实现完整 Office 编辑器。
- 终端是未来高级后备能力；如果手机本地 Capability 足够强，第一版本可以完全不实现终端。
- 远端运行时只保留抽象入口，不作为第一版本验收条件。
- 第一版本默认使用阿里云百炼 OpenAI 兼容接口接入 `glm-5` 进行模型联调；面向用户的模型设置页当前只要求填写百炼通用 API Key，其它上下文和生成参数使用推荐默认值。

## 核心流程

### 多轮对话与工具调用

1. 用户在当前 Workspace 中发起对话，可输入文字、图片、文件或系统分享内容。
2. 系统把全局长期记忆、同一会话上下文、当前 Workspace 数据上下文、附件摘要和可用 Capability 一起提供给 Agent；用户不应需要重复告诉 AI 已保存的偏好、稳定事实或本会话前面已经说过的关键信息。
3. Agent 必须在正式对话中以流式方式输出 Markdown，也可以通过 OpenAI 兼容工具调用协议发起工具调用、权限请求、TODO 更新、任务进度和 Artifact 创建。
4. Capability Runtime 校验工具输入、权限策略和执行边界后调用对应 adapter。
5. 工具结果以结构化结果返回给 Agent，并以工具轨迹展示给用户；联网搜索和网页解析结果必须优先展示为可读结果卡片，而不是只暴露原始 Map 文本。
6. Agent 基于工具结果继续回答；失败时说明原因并给出替代方案。
7. 单次用户请求的自动工具调用必须使用任务预算，而不是很低的固定演示轮数；预算至少要同时约束模型轮次、总工具调用次数和连续工具失败次数。
8. 任务预算应足以支持复杂任务的多步搜索、读取、记忆和本地能力调用；达到预算或连续失败保护时，系统必须停止继续调用工具，并要求 Agent 基于已有结果给出最终回答。
9. 普通对话必须使用当前已配置的模型提供方；若缺少 API Key，系统必须在对话中提示用户先完成模型设置。

### 模型配置

1. 用户可以进入模型设置页选择模型厂商。
2. 第一版本内置阿里云百炼 `glm-5` 配置。
3. 用户当前只需要填写和保存 API Key。
4. 系统必须安全保存 API Key，不把密钥写入普通日志、对话消息或 Artifact。
5. 系统提供测试连接入口，用默认推荐参数向当前模型发起最小请求，并把成功或失败原因反馈给用户。

### Artifact 创建与复用

1. AI 生成或处理出的可复用内容必须进入 Artifact Store。
2. 对话消息中展示 Artifact 卡片，不把大型真实内容只塞进消息文本。
3. Artifact 可归属当前 Workspace，并可被后续会话引用。
4. 第一版本 Artifact 类型包括文档、图片引用、表格、报告、笔记、任务清单、生成文件和 Web App。

### Workspace 与记忆

1. 系统必须默认创建一个默认 Workspace。
2. 用户可以创建工作、学习、生活等 Workspace。
3. Workspace 用于区分会话、文件、Artifact、Web App、任务流程和工作数据，但不切分用户的长期记忆。
4. 回答时默认使用全局长期记忆和当前 Workspace 数据上下文。
5. 用户可以查看、编辑或删除全局长期记忆；第一版不提供按 Workspace 隔离的长期记忆。

### Web 小应用

1. 用户可以让 AI 创建一个本地 Web App。
2. AI 生成 Web App manifest、入口文件和资源文件。
3. Web App 写入本地应用库，并作为 Web App Artifact 展示。
4. 每个 Web App 有独立文件目录、数据库 namespace、权限记录和 manifest。
5. Web App 首次运行时按 manifest 请求权限。
6. Web App 通过 JSBridge 调用受控 Capability。
7. 权限拒绝、能力不可用或调用失败时，JSBridge 返回结构化错误。

### Skill 与 MCP

1. Skill 遵循 Agent Skills / Claude Code 当前规范，不自定义新 Skill 格式。
2. 用户可以从本地目录、zip 或 Git URL 安装 Skill。
3. 系统扫描、索引并按 progressive disclosure 加载 Skill。
4. `allowed-tools` 只能映射到本项目权限策略，不直接无条件放权。
5. 脚本执行必须走 Capability Runtime；无可用执行后端时返回明确不可用。
6. MCP 第一版本优先支持 HTTP/SSE 类连接；stdio MCP、Android 本机进程执行和终端能力仅保留扩展入口。

## 组件与边界

- Conversation Runtime：负责会话、消息、流式事件、工具事件、任务进度和对话状态。
- Agent Event Stream：统一承载文本、工具调用、工具结果、权限请求、TODO、进度、错误和 Artifact 事件。
- MessageBlock Renderer：渲染 Markdown、代码块、图片、附件、工具轨迹、权限卡、进度、TODO、引用、Artifact 卡片、Web App 卡片和错误卡片。
- Artifact Store：保存可复用产物及其归属、类型、元数据和内容位置。
- Memory Store：保存用户全局长期记忆。
- Workspace Store：保存 Workspace、当前工作区、工作区内会话、文件、Artifact、Web App 和任务数据。
- Model Settings：保存模型厂商、默认模型、默认参数和用户 API Key。
- Capability Runtime：统一注册、发现、校验和调度所有能力。
- Permission Policy：把用户三档权限模式、Capability 风险等级和高级配置映射为允许、询问或拒绝。
- Audit Log：记录所有 Capability 调用、权限决策、执行结果和失败原因。
- App Log：记录应用运行、模型请求、Capability 调用、联网搜索、异常和诊断信息；控制台至少输出 info 以上级别日志，本地必须写入可定位的日志文件。
- Native / Search / File / DB / MCP / Skill / WebView adapters：实现具体能力来源。

## 数据与状态语义

- Workspace 是组织方式，不是强隔离人格；用户长期记忆不按 Workspace 切分，默认在所有 Workspace 中可用。
- 会话上下文必须优先保留最近消息原文；当上下文过长时，较早消息应压缩为摘要继续提供给 Agent。
- 会话压缩摘要必须保留用户目标、关键事实、已完成动作、工具结果、Artifact、未解决问题和明确约束；最近消息原文优先级高于压缩摘要。
- 会话上下文、Workspace 数据上下文和全局长期记忆是三种不同来源：会话上下文服务当前连续任务，Workspace 数据上下文服务当前工作区的数据组织，全局长期记忆服务跨场景稳定偏好和事实。
- Note 是 Workspace 数据，不是用户长期记忆；它用于保存当前工作区内的备忘、事项、资料摘录和可复用文本记录。
- Note 必须写入设备本地数据库；应用重启后，当前 Workspace 内已经保存的 Note 仍应可展示和查询。
- `db.note.query` 默认只返回当前 Workspace 的 Note，不能把其它 Workspace 的 Note 混入当前工作区结果。
- App File 是 Workspace 数据；`file.write_app_file` 和 `file.read_app_file` 只能访问当前 Workspace 的应用沙箱文件。
- App File 路径必须是相对路径；绝对路径、空路径和路径穿越必须返回结构化错误，不能访问系统任意文件或其它 Workspace 文件。
- 长期记忆会自动注入普通对话上下文；Agent 不需要为了使用已注入的长期记忆而先调用 `memory.query`。
- `memory.query` 只用于用户询问“你记住了什么”、盘点或管理大量记忆等显式记忆管理场景。
- 长期记忆只保存用户长期偏好、身份信息、常用规则和跨场景稳定事实；当前对话短期状态由会话上下文承载，不写成长记忆。
- MessageBlock 是对话 UI 的基本渲染单位，第一版本必须支持：
  - `markdown_text`
  - `code_block`
  - `image`
  - `file_attachment`
  - `tool_call`
  - `tool_result`
  - `approval_request`
  - `task_progress`
  - `todo_list`
  - `citation`
  - `artifact_card`
  - `web_app_card`
  - `error_card`
- Capability 必须声明 id、描述、输入 schema、输出 schema、风险等级、权限需求和 adapter。
- 内建能力、MCP、Skill、WebView Bridge、手机原生能力都必须走同一个权限和审计层。
- 面向用户只提供三档权限模式：默认权限、自动审查、完全访问权限。
- 高级用户后续可以通过配置文件自定义 allowlist 和 denylist。
- 默认模式下，高风险能力必须确认；完全访问权限也必须保留审计日志。
- 当前默认模型提供方为阿里云百炼，默认模型为 `glm-5`，默认 OpenAI 兼容 Base URL 为 `https://dashscope.aliyuncs.com/compatible-mode/v1/`。
- `glm-5` 当前推荐默认参数为普通模式、不启用思考、`temperature=1.0`、`top_p=0.95`、`top_k=20`；正式对话默认 `stream=true`，连接测试可以使用非流式请求；第一版本不在普通设置页暴露这些参数。
- API Key 是用户敏感凭证，必须保存在安全存储中。
- 日志不得泄露完整 API Key；写入控制台或本地文件前必须对密钥形态进行脱敏。

## 当前阶段边界

当前阶段包含：

- Android/iOS Flutter 项目骨架。
- 默认 Workspace 和用户新建 Workspace。
- 多轮对话、流式输出语义、Markdown、代码块、表格和基础消息块。
- 图片输入、文件输入和系统分享入口的业务入口。
- 联网搜索和网页读取能力的 Capability 定义。
- 文件、数据库、记忆、Workspace、Artifact、定位、剪贴板、通知、设备信息、WebView、Skill 和 MCP 的 Capability 定义。
- Artifact 中心。
- 全局长期记忆和会话上下文。
- 模型设置页，支持阿里云百炼 `glm-5` API Key 保存和连接测试。
- 正式对话的最小 Agent Loop：模型流式输出、自动发起工具调用、Capability Runtime 执行工具、工具结果回传模型、模型继续回答。
- Agent Loop 必须具备可调任务预算，并在日志中暴露当前工具调用消耗，方便定位过早停止或循环调用。
- Agent Loop 必须携带同一会话的近期原文上下文，并在上下文过长时携带较早内容的压缩摘要。
- 第一批接入 Agent Loop 的真实内建能力是 `memory.create`、`memory.query`、`memory.delete`、`db.note.create`、`db.note.query`、`file.write_app_file`、`file.read_app_file`、`artifact.create`、`artifact.query`、`workspace.create`、`workspace.switch`、`device.info`、`clipboard.read`、`clipboard.write`、`location.get_current` 和 `notification.schedule`。
- 当用户要求新建或切换工作区时，Agent 可以调用 `workspace.create` 或 `workspace.switch`；创建成功后当前 Workspace 必须切换到新工作区，切换目标不存在时必须返回结构化错误。
- 当用户要求记录备忘、保存信息、整理事项或查询已保存笔记时，Agent 可以调用 `db.note.create` 或 `db.note.query` 读写当前 Workspace 的 Note。
- `db.note.create` 写入的 Note 必须落到设备本地数据库，而不是只停留在当前进程内存。
- 当用户要求创建、保存、读取或修改当前工作区文件时，Agent 可以调用 `file.write_app_file` 或 `file.read_app_file` 读写当前 Workspace 的 App File。
- `file.write_app_file` 写入的文件必须落到当前 Workspace 的应用沙箱文件目录；`file.read_app_file` 只能读取同一 Workspace 的 App File。
- 当用户要求查看当前设备环境、读取剪贴板或复制内容时，Agent 可以调用 `device.info`、`clipboard.read` 或 `clipboard.write`；剪贴板读取不应在用户未明确要求时主动触发。
- 当用户明确要求使用当前位置时，Agent 可以调用 `location.get_current`；定位服务关闭、权限拒绝、永久拒绝或平台异常时必须返回结构化错误。
- 当用户明确要求稍后提醒或安排本地通知时，Agent 可以调用 `notification.schedule`；通知权限拒绝、初始化失败、无效时间或平台异常时必须返回结构化错误。
- 当 Agent 生成报告、文档、任务清单、文件摘要或 Web App 等可复用产物时，可以调用 `artifact.create` 写入当前 Workspace 的 Artifact，并在对话中展示 Artifact 卡片或 Web App 卡片。
- `artifact.query` 只能查询当前 Workspace 的 Artifact，不能把其它 Workspace 的产物混入当前工作区结果。
- `web.search` 和 `web.fetch` 必须通过 Capability Runtime 接入 Agent Loop；搜索返回结构化结果，网页读取返回适合模型继续处理的正文文本。
- `web.search` 第一优先级使用阿里云百炼 WebSearch MCP，并复用用户已经保存的百炼通用 API Key；如果未配置 API Key，必须返回结构化未配置错误。
- `web.fetch` 第一阶段通过阿里云百炼 WebSearch MCP 对目标 URL 发起抓取和解析请求；如果需要更专用的网页抓取 MCP，后续可接入百炼 MCP 广场对应服务。
- `web.search` 和 `web.fetch` 的对话展示必须包含状态、Provider、查询或 URL、正文摘要和可识别的来源链接；失败时必须清晰展示错误原因。
- WebView 小应用运行时、manifest 语义和 JSBridge 语义。
- Agent Skills / Claude Code 风格 Skill 的安装、扫描、索引和受控调用语义。
- HTTP/SSE 类 MCP 连接语义和失败处理。
- 权限三档、权限请求、权限拒绝和审计日志。

当前阶段不包含：

- 语音输入或输出。
- 远程终端。
- 云端运行时。
- 后台长期自主任务。
- 插件市场。
- 任意网页默认调用手机能力。
- iOS 本机 shell。
- 完整 Office 编辑器。

## 验收标准

- 用户能在默认 Workspace 中与 AI 多轮对话，回复正确渲染 Markdown、代码块和表格。
- 用户能新建 Workspace，并在不同 Workspace 中看到各自的会话、文件、Artifact、Web App 和任务数据。
- AI 回答时能自动使用全局长期记忆；切换 Workspace 不会让 AI 忘记用户长期偏好和稳定事实。
- AI 能在用户明确要求记住长期偏好、事实或规则时调用 `memory.create`，在用户明确询问或管理记忆时调用 `memory.query`，并在工具结果返回后继续完成自然语言回答。
- AI 能在用户明确要求忘记某条长期记忆时调用 `memory.delete`。
- 用户能查看、编辑、删除全局长期记忆。
- 用户上传文件后，AI 能总结、问答，并生成 Artifact。
- 用户上传图片后，AI 能识别图片内容或提取文字。
- 用户能在模型设置页只填写阿里云百炼 API Key，并使用内置 `glm-5` 默认配置测试连接。
- 用户保存阿里云百炼 API Key 后，普通对话能调用内置 `glm-5` 配置获得模型回复。
- 普通对话回复应在生成过程中持续更新到对话流中，并在用户仍停留在底部附近时自动滚动到最新内容；如果用户主动向上浏览历史消息，当前流式输出不得强制抢回滚动位置，直到用户重新回到底部附近才恢复自动追底。
- AI 能自动调用 `web.search` 和 `web.fetch` 回答需要联网的问题，并展示调用轨迹和来源。
- AI 在复杂任务中能连续完成超过三轮的工具调用；除非达到任务预算、连续失败保护、权限拒绝或模型自然结束，系统不得过早停止工具链。
- `web.search` 或 `web.fetch` 的网络请求、解析或读取失败时，系统必须向 Agent 返回结构化错误，不能导致对话或应用崩溃。
- AI 能调用本地数据库创建和查询 Note；Note 归属当前 Workspace，切换 Workspace 后不会展示或查询到其它 Workspace 的 Note。
- 应用重启后，用户此前通过 `db.note.create` 保存的 Note 仍能在对应 Workspace 中展示，并能被 `db.note.query` 查询到。
- AI 能调用 `workspace.create` 创建 Workspace 并切换过去，也能调用 `workspace.switch` 切换到已有 Workspace；目标不存在时不得崩溃。
- AI 能调用 `file.write_app_file` 和 `file.read_app_file` 在当前 Workspace 应用沙箱内写入和读取文本文件；切换 Workspace 后不能读取其它 Workspace 的文件。
- `file.write_app_file` 和 `file.read_app_file` 对空路径、绝对路径、路径穿越、文件不存在和覆盖冲突必须返回结构化错误。
- AI 能在用户明确要求时读取设备基础信息、读取剪贴板纯文本或写入剪贴板，并在对话中展示工具轨迹。
- AI 能在用户明确要求时获取当前位置；定位服务关闭或用户拒绝授权时，系统不崩溃，并把结构化失败原因返回给 Agent。
- AI 能在用户明确要求时安排本地系统通知；通知权限拒绝、无效提醒时间或平台不可用时，系统不崩溃，并把结构化失败原因返回给 Agent。
- AI 能调用 `artifact.create` 创建当前 Workspace 的 Artifact，并在对话中展示对应 Artifact 卡片；`artifact.query` 只返回当前 Workspace 的 Artifact。
- AI 能生成一个本地 Web App，该 App 出现在应用库并可单独打开。
- Web App 首次运行时按 manifest 请求权限，拒绝后 JSBridge 调用返回结构化错误。
- 两个 Web App 不能互相读取文件目录和数据库 namespace。
- Skill 可从目录、zip 或 Git URL 安装、扫描、索引、触发。
- 含 `scripts/` 的 Skill 不会绕过权限层执行。
- MCP 连接失败、Skill 格式错误、权限拒绝、定位拒绝时，系统不崩溃，并向 AI 返回结构化错误。

## 失败处理

- Capability 输入不合法时，返回结构化参数错误并记录审计日志。
- 权限不足或用户拒绝时，返回结构化权限错误，不执行实际能力。
- 平台能力不可用时，返回能力不可用错误，并允许 Agent 给出替代方案。
- MCP 连接失败时，保留配置和失败原因，不影响其他 Capability。
- Skill 格式错误时，阻止安装或标记不可用，并暴露可读错误。
- Web App 调用未授权 Capability 时，JSBridge 返回拒绝错误，不暴露底层异常。
- 文件、Artifact 或 Workspace 不存在时，返回明确的 not found 错误。
- 模型 API Key 缺失时，模型连接测试必须提示用户先填写 API Key。
- 模型连接失败时，系统必须展示 HTTP 状态或可读错误原因，不泄露完整密钥。
- 搜索服务不可达、搜索结果解析失败、网页读取超时、目标 URL 无效或目标网页不可读时，联网能力必须返回结构化错误，并允许 Agent 解释限制或尝试替代方案。
- 应用日志初始化失败不能阻断应用启动；日志文件写入失败时至少保留控制台错误。

## 关键不变量

- AI 永远不能绕过 Capability Runtime 直接调用手机能力、MCP、Skill、文件、数据库或 WebView Bridge。
- 所有高风险能力调用必须经过权限策略；完全访问权限也不能关闭审计日志。
- Workspace 不能阻断全局长期记忆的默认可用性。
- Web App 默认只加载本地沙箱内容；任意外部网页默认不能调用手机能力。
- Web App 之间默认文件目录和数据库 namespace 隔离。
- Skill 格式必须跟随 Agent Skills / Claude Code 生态，不能为了移动端自定义不兼容格式。
- 对话中的可复用产物必须进入 Artifact Store，不能只存在于消息文本。

## 关键决策

- 第一版本以移动端多模态 Agent 工作台和手机本地能力基座为定位。
- Capability Runtime 是所有能力的统一入口。
- Web 小应用是 Artifact 的高级形态，而不是产品唯一目标。
- Workspace 是组织方式，不是强隔离人格。
- 长期记忆是全局的，不按 Workspace 切分；会话短期状态由会话上下文和压缩摘要承载。
- Skill 遵循 Agent Skills / Claude Code 当前规范。
- 第一版本不实现远程终端和云端运行时。
- 第一版本不实现语音输入或输出。
- 第一版本默认以阿里云百炼 `glm-5` 作为模型联调入口，普通用户只配置百炼通用 API Key。
- 第一版先以记忆工具验证自动多轮工具调用闭环，再把同一机制扩展到联网搜索、文件、数据库、Skill、MCP 和手机原生能力。
- 联网搜索和网页读取复用同一 Agent Loop 与 Capability Runtime，不走 UI 层或 controller 的特殊分支。
- 阿里云百炼 WebSearch MCP 是第一版默认搜索 Provider，因为它能复用百炼通用 API Key、国内可用性更好，并与后续 MCP 架构一致。
- 阿里云百炼 WebSearch MCP 当前同时承载搜索和 URL 解析请求；如果后续接入专用网页抓取 MCP，仍必须走 Capability Runtime。

## 非目标

- 语音输入或输出。
- 远程终端。
- 云端运行时。
- 后台长期自主任务。
- 插件市场。
- 任意网页默认调用手机能力。
- iOS 本机 shell。
- 完整 Office 编辑器。

## 开放问题

- 图片理解/OCR、PDF 解析和网页搜索的具体 provider 可以随实现阶段选择，但不得改变本规格定义的业务能力。
- 多厂商模型参数暴露方式后续实现模型编排时再确认；普通设置页当前只暴露 API Key。
