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
- 第一版本默认使用阿里云百炼 OpenAI 兼容接口接入 `qwen3.6-flash-2026-04-16` 进行模型联调；面向用户的模型设置页允许填写百炼通用 API Key，并可覆盖模型名称，其它上下文和生成参数使用推荐默认值。

## 核心流程

### 多轮对话与工具调用

1. 用户在当前 Workspace 中发起对话，可输入文字、图片、文件或系统分享内容。
2. 系统把全局长期记忆、同一会话上下文、当前 Workspace 数据上下文、附件摘要和可用 Capability 一起提供给 Agent；用户不应需要重复告诉 AI 已保存的偏好、稳定事实或本会话前面已经说过的关键信息。
3. 系统必须先通过结构化工具路由步骤，基于用户最新消息、近期上下文和真实 Capability 描述选择本轮需要暴露的最小工具集合；近期对话只能作为模型路由的语义消歧输入，不能让上一轮 assistant 能力介绍或系统提示独立触发工具 schema 或必需工具；路由结果必须经过真实工具名白名单校验；普通聊天不应默认暴露全量工具 schema，未暴露的工具组视为本轮不可用，以降低 token 消耗和误调用概率。
4. Agent 必须在正式对话中以流式方式输出 Markdown，也可以通过 OpenAI 兼容工具调用协议发起工具调用、权限请求、TODO 更新、任务进度和 Artifact 创建。
5. 每次 Agent 运行都必须向 UI 和日志持续报告当前阶段，例如工具规划、模型流式响应、等待工具调用、执行工具、等待前台和整理最终回答；用户不能只看到“发送中”而不知道当前卡在哪一步。
6. 用户必须能停止当前 Agent 运行；停止后输入区恢复可用，系统不能让一次卡住的模型流长期阻塞后续操作。
7. Capability Runtime 校验工具输入、权限策略和执行边界后调用对应 adapter。
8. 工具结果以结构化结果返回给 Agent，并以工具轨迹展示给用户；同一次用户请求中的中间模型轮次、工具调用和工具结果默认应收敛到同一个回复气泡的折叠执行过程里，最终回答和可复用产物卡片保持外露；模型准备工具调用前已经输出的临时说明或代码也应归入折叠过程，不能在生成中用大段源码淹没会话；联网搜索、网页解析和手机本地能力结果必须优先展示为用户可理解的摘要或结果卡片，原始结构化数据只能作为调试详情折叠展示。
9. Agent 基于工具结果继续回答；失败时说明原因并给出替代方案。
10. 模型流式连接必须有接收空闲超时；如果连接已经建立但长时间没有新 token、工具调用或完成事件，系统必须返回可诊断错误并恢复输入，而不是无限保持发送中。
11. 单次用户请求的自动工具调用必须使用任务预算，而不是很低的固定演示轮数；预算至少要同时约束模型轮次、总工具调用次数和连续工具失败次数。
12. 任务预算应足以支持复杂任务的多步搜索、读取、记忆和本地能力调用；达到预算或连续失败保护时，系统必须停止继续调用工具，并要求 Agent 基于已有结果给出最终回答。
13. 普通对话必须使用当前已配置的模型提供方；若缺少 API Key，系统必须在对话中提示用户先完成模型设置。

### 模型配置

1. 用户可以进入模型设置页选择模型运行模式，支持网络模型（阿里云百炼）与本地模型（Gemma）。
2. 网络模型：第一版本内置阿里云百炼 `qwen3.6-flash-2026-04-16` 配置。用户可以填写和保存 API Key，也可以修改模型名称。系统提供测试连接入口并安全保存 API Key。
3. 本地模型：第一版本引入 `gemma` 本地模型支持。用户选择本地模型时，系统不需要输入 API Key。
4. 模型下载与本地导入管理：
   - 模型设置页提供下载与导入卡片，展示本地 Gemma 模型的激活状态（未安装/已安装）。
   - 提供“自动下载”按钮，点击后利用后台下载服务下载并安装 Gemma 4 E4B 模型至本地。
   - 提供“导入本地文件”按钮，允许用户通过系统文件选择器选择传输到手机上的 `.litertlm` 模型文件，一键注册并安装模型，避开网络下载超时的限制。
   - 支持显示下载与导入的进度和状态，支持失败重试。
   - 允许用户在下载时输入 Hugging Face 令牌（Token）以支持 Gated 模型，并且支持自定义模型下载 URL。
5. 本地流式推理：本地模型下载并激活后，系统在调用推理时将自动路由到本地 Gemma 运行时执行本地流式推理，不依赖网络连接。
6. 连接测试：对于网络模型，测试接口的连通性；对于本地模型，检查本地模型文件是否存在并尝试初始化模型实例。

### Artifact 创建与复用

1. AI 生成或处理出的可复用内容必须进入 Artifact Store。
2. 对话消息中展示 Artifact 卡片，不把大型真实内容只塞进消息文本。
3. Artifact 可归属当前 Workspace，并可被后续会话引用。
4. 第一版本 Artifact 类型包括文档、图片引用、表格、报告、笔记、任务清单、生成文件和 Web App。
5. Web App Artifact 在对话中必须展示为可点击卡片；用户点击后进入独立预览页面，而不是只能从运行时面板打开。

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
8. Web App 运行时应在平台允许范围内启用本地 HTML/CSS/JS 所需的媒体播放、文件选择和受控设备权限请求；Android WebView 内核版本由系统 WebView 提供，应用只能配置运行能力，不能承诺内置升级内核。
9. AI 生成 Web App 时，凡网页脚本需要调用手机能力，都必须在 manifest/metadata permissions 中声明精确 Capability，并通过 `window.PhoneAgent.callCapability(id, input)` 调用，不能假装直接访问手机原生能力。
10. AI 生成 Web App 时默认按手机竖屏和触摸交互设计；页面必须适配常见手机宽度、安全区域和移动端性能，不应默认生成桌面优先、多列侧栏、依赖 hover 或密集小字号的布局。
11. Web App 运行时应把页面运行过程中的 warning、error、未捕获异常和未处理 Promise 拒绝写入该 Web App 项目目录下的运行日志，供后续 AI 维护时读取并结合用户反馈修复。
12. Web App Artifact 创建后必须支持同一项目的持续维护；用户反馈、修复或迭代已有 Web App 时，系统应更新原项目文件和原 Artifact 元数据，而不是默认复制一份新项目或创建新的预览卡片。
13. Web App 项目必须具备轻量版本记录；每次项目更新都应记录版本号、变更摘要、变更文件、项目文件快照和更新时间，使用户与 Agent 可以查看历史并回滚到已有版本。
14. Web App 项目维护必须允许在原项目目录内新增、覆盖或补丁修改资源文件，例如图片、SVG、CSS、JS 和 HTML；同时必须继续禁止路径穿越、绝对路径、跨 Workspace 或跨 Web App 项目写入。
15. Web App 创建或更新后应具备项目级受控测试能力；第一阶段测试边界是读取该项目 manifest 和项目文件做本地静态检查，发现入口缺失、文件引用缺失、明显 HTML/CSS/JS 结构问题等可诊断错误，不执行任意 shell、npm、网络测试或项目目录外访问。

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
- Model Settings：保存模型厂商、默认模型、用户覆盖的模型名称、默认参数和用户 API Key。
- Capability Runtime：统一注册、发现、校验和调度所有能力。
- Permission Policy：把用户三档权限模式、Capability 风险等级和高级配置映射为允许、询问或拒绝。
- System Permission Registry：统一记录手机系统权限的业务含义、当前授权状态、受影响 Capability、申请入口和系统设置入口。
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
- Web App 通过 JSBridge 调用数据库或文件类 Capability 时，必须使用该 Web App 独立的数据 namespace；同一 Workspace 下的两个 Web App 不能互相读取对方的 Note 或 App File。
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
- 手机系统运行时权限必须由统一权限申请服务检查和申请；手机原生 Capability 不应在各自 adapter 中分散实现权限申请流程。
- 用户在对话或 Web App 中触发需要手机系统权限的原生 Capability 时，系统必须在能力执行过程中自动检查并在平台允许时发起系统授权申请；用户不应必须先手动进入权限页授权。若权限被永久拒绝、系统服务关闭、受系统限制或平台不可用，能力必须返回结构化错误和面向用户的可读处理建议。
- 用户必须能在统一权限列表页查看当前系统权限状态；当权限可在 App 内申请时可以直接申请，当权限被永久拒绝、受系统限制、服务关闭或无法在 App 内恢复时，必须提供跳转系统设置的入口。
- 当前默认模型提供方为阿里云百炼，默认模型为 `qwen3.6-flash-2026-04-16`，默认 OpenAI 兼容 Base URL 为 `https://dashscope.aliyuncs.com/compatible-mode/v1/`。
- `qwen3.6-flash-2026-04-16` 当前推荐默认参数为普通模式、不启用思考、`temperature=1.0`、`top_p=0.95`、`top_k=20`；正式对话默认 `stream=true`，连接测试可以使用非流式请求；第一版本不在普通设置页暴露这些参数。
- API Key 是用户敏感凭证，必须保存在安全存储中。
- 日志不得泄露完整 API Key；写入控制台或本地文件前必须对密钥形态进行脱敏。
- 用户必须能手动清理本地工作区数据；清理范围包括 Workspace、会话、长期记忆、Note、Artifact、Web App、本地工作区文件和工具审计记录，但不得删除模型名称、模型提供方设置或 API Key。

## 当前阶段边界

当前阶段包含：

- Android/iOS Flutter 项目骨架。
- 默认 Workspace 和用户新建 Workspace。
- 多轮对话、流式输出语义、Markdown、代码块、表格和基础消息块。
- Markdown 渲染必须对流式输出中的临时未闭合标记具备容错能力，例如未闭合的粗体或行内代码标记，避免把明显的 Markdown 控制符直接暴露给用户。
- 图片输入、文件输入和系统分享入口的业务入口。
- 联网搜索和网页读取能力的 Capability 定义。
- 文件、数据库、记忆、Workspace、Artifact、Office/PDF 文档、时间、定位、剪贴板、相机、媒体选择、系统文件选择、麦克风录音、联系人选择、二维码/条码识别、通知、日历、设备信息、屏幕常亮与方向控制、系统音量控制、系统 UI 显隐控制、WebView、Skill 和 MCP 的 Capability 定义。
- Artifact 中心。
- 全局长期记忆和会话上下文。
- 模型设置页，支持阿里云百炼 API Key 保存、自定义模型名称、恢复默认模型和连接测试。
- 正式对话的最小 Agent Loop：模型流式输出、自动发起工具调用、Capability Runtime 执行工具、工具结果回传模型、模型继续回答。
- Agent Loop 必须具备可调任务预算，并在日志中暴露当前工具调用消耗，方便定位过早停止或循环调用。
- Agent Loop 必须携带同一会话的近期原文上下文，并在上下文过长时携带较早内容的压缩摘要。
- 第一批接入 Agent Loop 的真实内建能力是 `memory.create`、`memory.query`、`memory.delete`、`db.note.create`、`db.note.query`、`file.write_app_file`、`file.read_app_file`、`file.search_app_files`、`file.apply_text_patch`、`project.create_web_app`、`project.update_web_app`、`project.test_web_app`、`project.version_history`、`project.revert_web_app`、`artifact.create`、`artifact.query`、`workspace.create`、`workspace.switch`、`document.extract`、`document.generate`、`document.apply_text_patch`、`spreadsheet.extract`、`spreadsheet.generate`、`presentation.extract`、`presentation.generate`、`pdf.extract`、`pdf.generate`、`device.info`、`time.get_current`、`battery.status`、`network.status`、`clipboard.read`、`clipboard.write`、`camera.capture_photo`、`camera.capture_video`、`flashlight.set`、`flashlight.status`、`media.pick_image`、`media.pick_images`、`media.pick_video`、`file.pick_system_file`、`audio.record_start`、`audio.record_stop`、`audio.record_cancel`、`contacts.pick`、`barcode.scan_camera`、`barcode.scan_image`、`share.text`、`system.haptic_feedback`、`system.sound_alert`、`system.volume.set`、`system.volume.status`、`system.ui.set`、`system.ui.status`、`permission.open_settings`、`url.open_external`、`screen.keep_awake`、`screen.keep_awake_status`、`screen.brightness.set`、`screen.brightness.status`、`screen.orientation.set`、`screen.orientation.status`、`sensor.accelerometer.read`、`sensor.gyroscope.read`、`sensor.magnetometer.read`、`location.get_current`、`notification.schedule`、`notification.pending`、`notification.cancel`、`notification.cancel_all` 和 `calendar.event.create`。
- 当用户要求新建或切换工作区时，Agent 可以调用 `workspace.create` 或 `workspace.switch`；创建成功后当前 Workspace 必须切换到新工作区，切换目标不存在时必须返回结构化错误。
- 当用户要求记录备忘、保存信息、整理事项或查询已保存笔记时，Agent 可以调用 `db.note.create` 或 `db.note.query` 读写当前 Workspace 的 Note。
- `db.note.create` 写入的 Note 必须落到设备本地数据库，而不是只停留在当前进程内存。
- 当用户要求创建、保存、读取或修改当前工作区文件时，Agent 可以调用 `file.write_app_file`、`file.read_app_file` 或 `file.search_app_files` 读写和定位当前 Workspace 的 App File。
- `file.write_app_file` 写入的文件必须落到当前 Workspace 的应用沙箱文件目录；`file.read_app_file` 只能读取同一 Workspace 的 App File。
- `file.read_app_file` 必须支持只读取文件局部行范围；`file.search_app_files` 必须返回带文件路径、行号和上下文片段的搜索结果，使 Agent 能先定位问题再读取和修改。
- 当用户要求创建小游戏、交互网页、Web App、原型或本地可维护项目时，Agent 必须把真实项目文件写入当前 Workspace 文件区，并创建可预览的 Web App Artifact 作为本地索引；不能只输出代码块或自然语言承诺。Web App 默认按本地工程组织，包含入口文件和工程 manifest；除极小页面外，应拆分入口 HTML、样式和脚本文件，便于后续定位和修复。
- 对创建网页、网站、小游戏、Web App、原型或本地可维护项目这类真实产物请求，系统必须把真实创建 Capability 视为必需工具；在必需工具成功执行前，Agent 不得声称产物已经创建、已保存或可预览。若模型只用自然语言声称完成，系统必须拦截并重新要求调用必需工具；重试后仍未完成时，必须返回未创建的结构化错误。
- 当用户要求维护或迭代已生成的本地项目时，Agent 应先搜索或读取相关文件片段，再用精确文本补丁修改文件；需要新增图片、样式、脚本或其它资源时，应写入原 Web App 项目目录内并更新原项目文件清单；补丁原文无法唯一匹配、目标路径越界或试图跨项目写入时必须返回结构化错误，避免盲目覆盖。
- Web App 创建或更新后，Agent 应调用项目级测试能力检查原项目；测试失败时应基于错误继续修复，或在无法继续时向用户说明剩余问题和未通过项，不得在测试失败后声称项目完全完成。
- 当前 Workspace 的 App File 必须有可发现入口；用户可以在运行时区域查看当前 Workspace 文件列表，点击预览文本内容，并通过系统分享或保存入口导出文件。
- 第一版 Office/PDF 能力必须支持上传或导入后的 Word、Excel、PPT、PDF 文件内容提取，并让 Agent 基于提取文本完成总结、问答和审阅；扫描版 PDF 的 OCR 不作为第一版承诺。
- 第一版 Office/PDF 能力必须支持生成新的 `docx`、`xlsx`、`pptx` 和 `pdf` 文件，并写入当前 Workspace 文件区供用户预览、分享或导出。
- 第一版 Office/PDF 能力可以做受控局部文本替换并生成新文件，但不承诺保留复杂 Office 原格式；完整所见即所得编辑仍应交给外部 App 或后续 OnlyOffice/Collabora 类适配。
- 当用户要求查看当前设备环境、读取剪贴板或复制内容时，Agent 可以调用 `device.info`、`clipboard.read` 或 `clipboard.write`；设备信息结果必须包含面向用户的摘要和规范化平台、型号、系统版本等基础字段；剪贴板读取不应在用户未明确要求时主动触发。
- 当用户明确要求拍照、拍视频、从相册选择单张图片、多张图片或视频、从系统文件选择器选择文件时，Agent 可以调用 `camera.capture_photo`、`camera.capture_video`、`media.pick_image`、`media.pick_images`、`media.pick_video` 或 `file.pick_system_file`；这些能力必须触发系统 UI 并允许用户取消，成功时返回文件名、本地 URI、媒体类型、MIME 类型和大小等结构化元数据，多图选择还必须返回数量和每张图片的结构化元数据列表。
- 当用户明确要求打开、关闭或查询手机手电筒/闪光灯硬件时，Agent 可以调用 `flashlight.set` 或 `flashlight.status`；打开或关闭必须检查相机权限并返回是否可用、是否开启和可读摘要，设备无闪光灯、权限拒绝或平台异常时必须返回结构化错误。该能力控制手机硬件，不用于网页视觉闪光效果。
- 当用户明确要求开始、停止或取消录音时，Agent 可以调用 `audio.record_start`、`audio.record_stop` 或 `audio.record_cancel`；同一时间只能有一个麦克风录音会话，停止成功时必须返回音频文件元数据，没有活跃录音时必须返回结构化错误。
- 当用户明确要求选择联系人、从通讯录导入联系人或本地 Web App 需要联系人输入时，Agent 可以调用 `contacts.pick`；该能力必须触发用户选择流程，只返回用户选中的单个联系人姓名、电话和邮箱等结构化信息，不能读取或返回完整通讯录。
- 当用户明确要求扫描二维码/条码，或识别图片、截图、照片中的二维码/条码时，Agent 可以调用 `barcode.scan_camera` 或 `barcode.scan_image`；这些能力必须由用户触发系统相机或图片选择流程，成功时返回码值、显示值、格式、类型和数量等结构化结果，用户取消或未识别到码时返回结构化失败。
- 当用户要求查看电量或网络连接类型时，Agent 可以调用 `battery.status` 或 `network.status`；电量和网络结果必须包含面向用户的摘要；网络状态只表示设备连接类型，不能等同于目标网站或互联网一定可达。
- 当用户明确要求分享文本、触感反馈、系统提示音或打开应用权限设置时，Agent 可以调用 `share.text`、`system.haptic_feedback`、`system.sound_alert` 或 `permission.open_settings`；分享和设置能力会触发系统 UI，需要用户继续确认或操作。
- 当用户明确要求调高、调低、静音、取消静音或查询设备媒体音量时，Agent 可以调用 `system.volume.set` 或 `system.volume.status`；音量值必须是 0 到 1 的比例，并返回当前音量、音量流类型、平台是否支持静默设置和可读摘要。该能力只承诺媒体/当前输出音量，不承诺修改铃声、闹钟、通话等所有系统音量；平台不允许静默设置时必须返回结构化 unsupported。
- 当用户明确要求进入全屏、沉浸式、隐藏或恢复状态栏和导航栏，或本地 Web App/游戏/演示需要调整当前应用的系统栏可见性时，Agent 可以调用 `system.ui.set`；需要查询当前系统 UI 显隐状态时可以调用 `system.ui.status`。该能力只影响当前应用的展示模式，不承诺修改系统全局设置。
- 当用户明确要求打开外部链接、电话、短信、邮件或地理 URI 时，Agent 可以调用 `url.open_external`；该能力只允许受支持的外部 URI scheme，并会跳出当前应用或打开系统 UI。
- 当用户明确要求长时间展示、计时器、演示或防止屏幕熄灭时，Agent 可以调用 `screen.keep_awake` 设置当前应用保持屏幕常亮，也可以调用 `screen.keep_awake_status` 查询当前状态；该能力只影响当前应用运行期间。
- 当用户明确要求调亮、调暗、设置或查询屏幕亮度，或本地 Web App/演示需要临时调整亮度时，Agent 可以调用 `screen.brightness.set` 或 `screen.brightness.status`；亮度值必须是 0 到 1 的比例，并返回当前亮度、是否使用系统默认亮度和可读摘要。该能力只承诺影响当前应用或平台允许的当前屏幕亮度，不承诺修改系统全局永久亮度。
- 当用户明确要求横屏、竖屏、锁定方向、解锁方向、恢复自动旋转，或本地 Web App/游戏/演示需要固定显示方向时，Agent 可以调用 `screen.orientation.set` 设置当前应用的屏幕方向偏好，也可以调用 `screen.orientation.status` 查询当前状态；该能力只影响当前应用，不承诺修改系统全局自动旋转设置。
- 当用户明确要求使用运动、姿态、方向或磁场信息时，Agent 可以调用 `sensor.accelerometer.read`、`sensor.gyroscope.read` 或 `sensor.magnetometer.read` 读取一次传感器快照；传感器不可用、超时或平台异常时必须返回结构化错误。
- 每轮对话必须把设备当前本地时间、UTC 时间或时区语义提供给 Agent；当用户询问当前时间，或安排通知/日历前需要校准相对时间时，Agent 可以调用 `time.get_current` 获取设备当前时间。
- 当用户明确要求使用当前位置时，Agent 可以调用 `location.get_current`；移动端定位必须使用可配置的真实定位 Provider 获取当前定位，成功时返回经纬度、精度、时间戳、坐标系、Provider 诊断、地址信息和面向用户的摘要；定位 Provider 所需平台 Key 必须通过本地不提交的运行配置注入，不能写入仓库或日志；定位服务关闭、权限拒绝、永久拒绝、缺少平台 Key、定位超时或平台异常时必须返回结构化错误和可读处理建议。
- 定位结果卡片必须提供地图查看入口；地图页应使用同一套本地注入的平台 Key 和受控隐私声明展示定位点，缺少平台 Key 或平台不支持时不得假装展示地图。
- 当用户明确要求稍后提醒或安排本地通知时，Agent 可以调用 `notification.schedule`；相对时间必须基于设备当前本地时间换算；本地通知不是系统时钟闹钟，也不写入系统日历；通知权限拒绝、初始化失败、无效时间或平台异常时必须返回结构化错误。用户要求查看或取消提醒时，Agent 可以调用 `notification.pending`、`notification.cancel` 或 `notification.cancel_all`；取消单条通知必须基于明确的通知 ID，清空全部通知必须来自用户明确要求。
- 当用户明确要求加入日历、创建日程、安排会议或保存日历事件时，Agent 可以调用 `calendar.event.create`；相对时间必须基于设备当前本地时间换算；该能力必须进入系统日历添加事件流程，由用户确认保存；时间无效、用户取消、平台不可用或平台异常时必须返回结构化结果。
- 当 Agent 生成报告、文档、任务清单、文件摘要或 Web App 等可复用产物时，可以调用 `artifact.create` 写入当前 Workspace 的 Artifact，并在对话中展示 Artifact 卡片或 Web App 卡片；需要卡片或预览入口时，Agent 不得只在 Markdown 正文中伪造 Artifact/Web App 链接。
- `artifact.query` 只能查询当前 Workspace 的 Artifact，不能把其它 Workspace 的产物混入当前工作区结果。
- `web.search` 和 `web.fetch` 必须通过 Capability Runtime 接入 Agent Loop；搜索返回结构化结果，网页读取返回适合模型继续处理的正文文本。
- `web.search` 第一优先级使用阿里云百炼 WebSearch MCP，并复用用户已经保存的百炼通用 API Key；如果未配置 API Key，必须返回结构化未配置错误。
- `web.fetch` 第一阶段通过阿里云百炼 WebSearch MCP 对目标 URL 发起抓取和解析请求；如果需要更专用的网页抓取 MCP，后续可接入百炼 MCP 广场对应服务。
- `web.search` 和 `web.fetch` 的对话展示必须包含状态、Provider、查询或 URL、正文摘要和可识别的来源链接；失败时必须清晰展示错误原因。
- WebView 小应用运行时、manifest 语义和 JSBridge 语义。
- Web App Artifact 可以从应用库打开；本地 Web App 通过 `window.PhoneAgent.getManifest()` 获取 manifest，通过 `window.PhoneAgent.callCapability(id, input)` 调用 manifest 已声明权限内的 Capability。
- Web App 运行时必须向页面暴露可发现的 JSBridge 契约，至少包括 manifest 读取、可用 Capability 列表和 Capability 调用入口，便于 AI 生成的网页自检权限和能力。
- Web App JSBridge 必须提供设备信息、手电筒等常用能力的可发现调用方式；页面需要设备信息或受控硬件能力时应通过已声明权限的 JSBridge 调用，而不是依赖浏览器伪造的设备环境。
- 对话中的 Web App 卡片必须能直接打开同一个 Web App 预览页面，并以清晰的本地应用入口样式展示标题、类型和打开操作。
- Web App Artifact 必须保存可运行入口内容和可发现的工程 manifest。缺少可运行入口内容时不得展示成“已加载”的假预览，必须返回结构化错误或可诊断提示。
- Web App 打开前必须向用户展示 manifest 声明的能力权限；用户拒绝后 Web App 仍可打开，但 JSBridge 能力调用必须返回结构化权限错误。
- Web App JSBridge 调用必须回到 Capability Runtime；未在 manifest 权限中声明的能力必须返回结构化拒绝错误。
- Web App 内网页请求相机、麦克风、定位、文件选择或媒体自动播放时，运行时只能在用户已批准该 Web App 权限门后放行；用户未批准时必须拒绝或返回空结果。
- Web App JSBridge 发起的 `db.note.create`、`db.note.query`、`file.write_app_file` 和 `file.read_app_file` 必须落到该 Web App 的独立 namespace。
- Web App 运行日志必须写入当前 Workspace 的普通项目文件区，使用户和 Agent 能在后续维护中通过文件列表或 `file.read_app_file` 查看；日志写入失败不能阻断 Web App 打开。
- Agent Skills / Claude Code 风格 Skill 的安装、扫描、索引和受控调用语义。
- HTTP/SSE 类 MCP 连接语义和失败处理。
- 权限三档、权限请求、权限拒绝和审计日志。
- 统一系统权限管理页和统一系统权限申请服务；当前覆盖已接入手机原生能力需要的定位、通知、相机、麦克风和联系人权限，并能展示这些权限影响的 Capability；相机权限同时影响拍照、拍视频、扫码和手电筒控制。

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
- 用户上传或导入 Word、Excel、PPT、PDF 后，AI 能通过对应 `document.*`、`spreadsheet.*`、`presentation.*`、`pdf.*` Capability 提取文本，并基于文本总结、问答或审阅。
- AI 能生成新的 `docx`、`xlsx`、`pptx` 和 `pdf` 文件到当前 Workspace 文件区；用户可在文件列表中找到并导出。
- AI 能对文档提取文本做受控局部替换并生成新文件；当无法唯一匹配原文或会丢失复杂格式时，系统必须返回结构化结果并向用户说明边界。
- 用户上传图片后，AI 能识别图片内容或提取文字。
- 用户能在模型设置页填写阿里云百炼 API Key，并可使用内置默认模型或自定义模型名称测试连接。
- 用户保存阿里云百炼 API Key 后，普通对话能调用当前配置的模型名称获得模型回复；未自定义时使用内置 `qwen3.6-flash-2026-04-16` 默认配置。
- 用户能从应用内清理本地工作区数据；清理后只保留默认 Workspace，工作区会话、文件、Note、Artifact、Web App、长期记忆和工具审计记录被清空，模型名称和 API Key 仍保留。
- 普通对话回复应在生成过程中持续更新到对话流中，并在用户仍停留在底部附近时自动滚动到最新内容；首次进入聊天界面默认定位到最近消息底部；聊天区域默认只加载最近一批会话消息，用户上滑到历史顶部时继续加载更早消息，避免一次性渲染完整历史；如果用户主动向上浏览历史消息，当前流式输出不得强制抢回滚动位置，直到用户重新回到底部附近才恢复自动追底；“滚动到底部”按钮只应在用户离底部较远时出现。
- 用户发送后必须能看到当前 Agent 运行阶段和可停止入口；停止入口应收敛在输入区发送按钮位置，发送中由“发送”切换为“停止”，不在输入框上方重复展示停止按钮；工具预算消耗保留在日志或诊断信息中，不要求作为输入框上方的常驻 UI 文案展示。模型流、工具执行或前后台恢复阶段卡住时，用户应能从 UI 和日志判断当前卡在哪一步。
- 模型流式连接如果在接收阶段空闲超时，系统必须向对话返回模型连接错误、恢复输入区，并在日志中记录 provider、model、阶段和是否可重试。
- 单次用户请求中的多轮 Agent 中间过程默认折叠展示；用户可展开查看工具调用、工具结果和中间输出，最终回答不应被中间过程淹没；Markdown 代码围栏在流式展示中应以折叠代码块呈现，避免网页源码、脚本或工具参数持续占据大面积会话空间。
- AI 能自动调用 `web.search` 和 `web.fetch` 回答需要联网的问题，并展示调用轨迹和来源。
- AI 在复杂任务中能连续完成超过三轮的工具调用；除非达到任务预算、连续失败保护、权限拒绝或模型自然结束，系统不得过早停止工具链。
- `web.search` 或 `web.fetch` 的网络请求、解析或读取失败时，系统必须向 Agent 返回结构化错误，不能导致对话或应用崩溃。
- AI 能调用本地数据库创建和查询 Note；Note 归属当前 Workspace，切换 Workspace 后不会展示或查询到其它 Workspace 的 Note。
- 应用重启后，用户此前通过 `db.note.create` 保存的 Note 仍能在对应 Workspace 中展示，并能被 `db.note.query` 查询到。
- AI 能调用 `workspace.create` 创建 Workspace 并切换过去，也能调用 `workspace.switch` 切换到已有 Workspace；目标不存在时不得崩溃。
- AI 能调用 `file.write_app_file` 和 `file.read_app_file` 在当前 Workspace 应用沙箱内写入和读取文本文件；切换 Workspace 后不能读取其它 Workspace 的文件。
- `file.write_app_file` 和 `file.read_app_file` 对空路径、绝对路径、路径穿越、文件不存在和覆盖冲突必须返回结构化错误。
- AI 能创建一个可维护的本地 Web 项目：项目文件出现在当前 Workspace 文件列表中，同时生成可点击预览的 Web App Artifact。
- 用户要求创建个人网页、网站、小游戏、Web App 或原型时，如果 Agent 未成功调用真实创建 Capability，系统不得展示“已创建”类最终回答或 Web App 卡片；成功时必须能看到项目文件和可点击 Web App Artifact。
- AI 能通过精确文本补丁维护当前 Workspace 内的项目文件；补丁目标不存在、不唯一或文件过大时不应修改文件，并返回可读错误。
- 用户反馈已生成 Web App 的运行问题时，AI 应优先读取该 Web App 的运行日志和相关项目文件，再定位并修复，而不是只根据用户描述猜测。
- 用户能在运行时页查看当前 Workspace 的 App File 列表；点击文件可预览文本内容，并可通过系统分享或保存入口导出到用户选择的位置。
- AI 能在用户明确要求时读取设备基础信息、读取剪贴板纯文本或写入剪贴板，并在对话中展示工具轨迹。
- AI 能在用户明确要求时调起系统相机拍照/拍视频、从相册选择图片或视频、从系统文件选择器选择文件、开始/停止/取消麦克风录音、从系统通讯录选择单个联系人，并能扫描或识别图片中的二维码/条码；用户取消选择、没有活跃录音或没有识别到码时返回结构化结果而不是崩溃或伪造成功。
- 手机本地能力执行后，对话中优先展示用户可理解的摘要或结论；原始工具元数据只作为折叠调试详情展示，不能把 JSON 或字段名直接当作最终回复。
- 工具结果给模型继续推理时应使用面向模型的精简 observation，而不是完整原始输出；完整输出只用于 UI 调试详情、审计日志和必要的后续精确读取，避免模型把工具调用过程或原始 Map 当作最终回答复述。
- 如果模型最终回复仍复述工具调用过程、原始 JSON、Map 或 Capability 元数据，系统必须把该回复视为不可用草稿，并让模型基于已有 observation 重新生成自然语言最终回答；系统不应把本地模板摘要伪装成 Agent 的最终回答。
- AI 能基于设备当前本地时间回答当前时间问题，并在安排通知或日历事件时用该时间解释今天、明天、今晚、几分钟后等相对表达。
- AI 能在用户明确要求时获取当前位置；如果尚未授权且平台允许 App 内申请，系统会在能力执行时自动发起系统授权申请；定位结果必须以真实定位 Provider 返回的经纬度、精度、时间戳、坐标系、地址信息和 provider 诊断为准，不得编造城市或地址；定位服务关闭、缺少平台 Key、定位超时或用户拒绝授权时，系统不崩溃，并把结构化失败原因和可读处理建议返回给 Agent。
- 用户能从成功的定位结果卡片打开地图查看定位点；地图无法初始化时必须显示可读原因，而不是显示空白页或假成功状态。
- AI 能在用户明确要求时安排、查看、取消单条或清空全部本地系统通知；通知权限拒绝、无效提醒时间或平台不可用时，系统不崩溃，并把结构化失败原因返回给 Agent。
- 用户能进入统一权限管理页查看定位和通知等系统权限状态；可申请的权限能在页内触发系统申请，无法在 App 内恢复的状态能跳转到系统设置。
- AI 能在用户明确要求时创建日历事件；系统必须打开平台日历添加事件流程，由用户确认保存，并在取消、时间无效或平台不可用时把结构化结果返回给 Agent。
- AI 能在用户明确要求时设置或查询当前 App 的系统 UI 显隐模式；全屏、沉浸式、边到边显示和恢复系统栏都必须返回结构化结果，并在对话中展示可读摘要。
- AI 能在用户明确要求时设置或查询当前 App 的屏幕方向偏好；横屏、竖屏、单方向锁定和恢复系统自动旋转都必须返回结构化结果，并在对话中展示可读摘要。
- AI 能调用 `artifact.create` 创建当前 Workspace 的 Artifact，并在对话中展示对应 Artifact 卡片；`artifact.query` 只返回当前 Workspace 的 Artifact。
- AI 能生成一个本地 Web App，该 App 出现在应用库并可单独打开。
- AI 生成 Web App 后，对话中展示的 Web App 卡片可以点击进入预览页面。
- Web App 预览必须渲染 Artifact 中保存的真实 HTML/CSS/JS 内容；如果 Artifact 缺少入口 HTML，系统必须明确提示缺失内容，不能只展示标题和“已加载”占位文案。
- Web App 预览打开时可启动仅绑定本机回环地址的临时本地服务来加载入口 HTML 和同项目相对资源；该服务只在预览页生命周期内存在，关闭预览页后必须停止，并且不得允许跨 Workspace 或路径穿越读取文件。
- Web App 首次运行时按 manifest 请求权限，拒绝后 JSBridge 调用返回结构化错误。
- Web App 能通过 JSBridge 调用已授权的内建 Capability；未授权 Capability 调用必须被拒绝，不能绕过 Capability Runtime。
- 用户或已授权 Web App 可以明确打开、关闭或查询手机手电筒；无闪光灯设备、权限拒绝或平台不可用时返回结构化错误和可读处理建议。
- 已授权 Web App 可以触发系统相册选择单张或多张图片；多图选择必须返回图片数量和每张图片的结构化元数据，用户取消时返回结构化取消结果。
- 已授权 Web App 可以临时设置或查询当前应用/当前屏幕亮度；亮度设置失败、平台不可用或参数越界时返回结构化错误。
- Web App 生成结果默认符合手机竖屏可用性：触摸目标足够大，内容在窄屏不横向溢出，关键操作不依赖 hover、键盘快捷键或桌面窗口尺寸。
- Web App 中的 HTML5 音视频、Web Audio、文件选择、摄像头、麦克风和定位请求在平台 WebView 支持时可按权限门运行；平台 WebView 本身不支持的浏览器 API 必须表现为明确不可用或页面侧可诊断失败，而不是伪造成功。
- Web App 运行时产生的 warning、error 和未捕获异常能被记录到项目文件夹中的运行日志；用户回到会话反馈问题后，AI 能读取该日志辅助修复。
- Web App 后续维护不会默认生成新项目；AI 能基于已有 Artifact、运行日志和项目文件更新原项目，允许在原项目目录内新增资源文件，并写入新的轻量版本记录。
- Web App 创建或更新后，AI 能对原项目执行受控静态测试；测试结果应返回是否通过、检查文件和问题列表，明显的入口缺失、引用缺失或 HTML/CSS/JS 结构问题不得被当作成功忽略。
- 用户或 Agent 能查询 Web App 项目的版本历史，并能把项目文件回滚到已有版本；回滚同样更新原 Artifact 元数据，不创建新的预览卡片。
- 两个 Web App 不能互相读取文件目录和数据库 namespace。
- Skill 可从目录、zip 或 Git URL 安装、扫描、索引、触发。
- 含 `scripts/` 的 Skill 不会绕过权限层执行。
- MCP 连接失败、Skill 格式错误、权限拒绝、定位拒绝时，系统不崩溃，并向 AI 返回结构化错误。

## 失败处理

- Capability 输入不合法时，返回结构化参数错误并记录审计日志。
- 权限不足或用户拒绝时，返回结构化权限错误，不执行实际能力。
- 手机系统权限未授权但仍可在 App 内申请时，原生能力执行流程应先发起系统授权申请；申请后仍被拒绝、永久拒绝、服务关闭或受限制时，返回结构化错误和面向用户的下一步建议。
- 平台能力不可用时，返回能力不可用错误，并允许 Agent 给出替代方案。
- MCP 连接失败时，保留配置和失败原因，不影响其他 Capability。
- Skill 格式错误时，阻止安装或标记不可用，并暴露可读错误。
- Web App 调用未授权 Capability 时，JSBridge 返回拒绝错误，不暴露底层异常。
- 平台 WebView 内核缺少某个浏览器 API 时，系统不承诺通过应用代码补齐浏览器内核能力；应暴露为可诊断限制，并优先引导网页改用 Phone Agent JSBridge 或已接入的 Capability。
- 文件、Artifact 或 Workspace 不存在时，返回明确的 not found 错误。
- 模型 API Key 缺失时，模型连接测试必须提示用户先填写 API Key。
- 模型连接失败时，系统必须展示 HTTP 状态或可读错误原因，不泄露完整密钥。
- 模型流式连接因应用切到后台、网络切换或系统关闭连接而中断时，系统必须展示可读错误；如果尚未收到任何模型正文或工具调用增量，可自动重试一次；如果重试发生时应用仍在后台，应等应用回到前台后再重试；一旦已收到正文或工具调用增量，不得自动重放同一轮模型请求，避免重复工具执行或重复内容。
- 搜索服务不可达、搜索结果解析失败、网页读取超时、目标 URL 无效或目标网页不可读时，联网能力必须返回结构化错误，并允许 Agent 解释限制或尝试替代方案。
- 应用日志初始化失败不能阻断应用启动；日志文件写入失败时至少保留控制台错误。

## 关键不变量

- AI 永远不能绕过 Capability Runtime 直接调用手机能力、MCP、Skill、文件、数据库或 WebView Bridge。
- 所有高风险能力调用必须经过权限策略；完全访问权限也不能关闭审计日志。
- Workspace 不能阻断全局长期记忆的默认可用性。
- Web App 默认只加载本地沙箱内容；任意外部网页默认不能调用手机能力。
- Web App 之间默认文件目录和数据库 namespace 隔离。
- Web App 运行时的网页平台权限必须受 Web App 权限门约束；允许媒体播放和文件选择不等于绕过 Capability Runtime 或系统权限。
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
- 第一版本默认以阿里云百炼 `qwen3.6-flash-2026-04-16` 作为模型联调入口，同时允许用户在设置页覆盖模型名称以切换同一接口下的可用模型。
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
- 多厂商模型参数暴露方式后续实现模型编排时再确认；普通设置页当前只暴露 API Key 和模型名称，不暴露温度、top_p、top_k 等高级生成参数。
