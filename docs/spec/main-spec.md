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

## 核心流程

### 多轮对话与工具调用

1. 用户在当前 Workspace 中发起对话，可输入文字、图片、文件或系统分享内容。
2. 系统把全局记忆、当前 Workspace 记忆、会话上下文、附件摘要和可用 Capability 一起提供给 Agent。
3. Agent 可以流式输出 Markdown，也可以发起工具调用、权限请求、TODO 更新、任务进度和 Artifact 创建。
4. Capability Runtime 校验工具输入、权限策略和执行边界后调用对应 adapter。
5. 工具结果以结构化结果返回给 Agent，并以工具轨迹展示给用户。
6. Agent 基于工具结果继续回答；失败时说明原因并给出替代方案。

### Artifact 创建与复用

1. AI 生成或处理出的可复用内容必须进入 Artifact Store。
2. 对话消息中展示 Artifact 卡片，不把大型真实内容只塞进消息文本。
3. Artifact 可归属当前 Workspace，并可被后续会话引用。
4. 第一版本 Artifact 类型包括文档、图片引用、表格、报告、笔记、任务清单、生成文件和 Web App。

### Workspace 与记忆

1. 系统必须默认创建一个默认 Workspace。
2. 用户可以创建工作、学习、生活等 Workspace。
3. Workspace 用于区分上下文、文件、Artifact、Web App、任务流程和局部记忆，但不把 AI 完全隔离。
4. 回答时默认同时使用全局记忆和当前 Workspace 记忆。
5. 用户可以要求某条记忆只属于当前 Workspace，也可以查看、编辑或删除全局记忆和 Workspace 记忆。

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
- Memory Store：保存全局记忆、Workspace 记忆和会话记忆。
- Workspace Store：保存 Workspace、当前工作区、工作区内会话、文件、Artifact、Web App 和局部记忆。
- Capability Runtime：统一注册、发现、校验和调度所有能力。
- Permission Policy：把用户三档权限模式、Capability 风险等级和高级配置映射为允许、询问或拒绝。
- Audit Log：记录所有 Capability 调用、权限决策、执行结果和失败原因。
- Native / Search / File / DB / MCP / Skill / WebView adapters：实现具体能力来源。

## 数据与状态语义

- Workspace 是组织方式，不是强隔离人格；全局记忆默认可跨 Workspace 使用。
- 记忆分三层：
  - 全局记忆：用户长期偏好、身份信息、常用规则、跨场景稳定事实。
  - Workspace 记忆：当前工作区内目标、文件、项目背景、流程记录和局部偏好。
  - 会话记忆：当前对话短期上下文和任务状态。
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

## 当前阶段边界

当前阶段包含：

- Android/iOS Flutter 项目骨架。
- 默认 Workspace 和用户新建 Workspace。
- 多轮对话、流式输出语义、Markdown、代码块、表格和基础消息块。
- 图片输入、文件输入和系统分享入口的业务入口。
- 联网搜索和网页读取能力的 Capability 定义。
- 文件、数据库、记忆、Workspace、Artifact、定位、剪贴板、通知、设备信息、WebView、Skill 和 MCP 的 Capability 定义。
- Artifact 中心。
- 全局记忆、Workspace 记忆和会话记忆。
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
- 用户能新建 Workspace，并在不同 Workspace 中看到各自的会话、文件、Artifact、Web App 和局部记忆。
- AI 回答时能同时使用全局记忆和当前 Workspace 记忆；用户可指定某条记忆仅保存在当前 Workspace。
- 用户能查看、编辑、删除全局记忆和 Workspace 记忆。
- 用户上传文件后，AI 能总结、问答，并生成 Artifact。
- 用户上传图片后，AI 能识别图片内容或提取文字。
- AI 能自动调用 `web.search` 和 `web.fetch` 回答需要联网的问题，并展示调用轨迹和来源。
- AI 能调用本地数据库创建和查询 note。
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

## 关键不变量

- AI 永远不能绕过 Capability Runtime 直接调用手机能力、MCP、Skill、文件、数据库或 WebView Bridge。
- 所有高风险能力调用必须经过权限策略；完全访问权限也不能关闭审计日志。
- Workspace 不能阻断全局记忆的默认可用性，除非用户显式限制某条记忆。
- Web App 默认只加载本地沙箱内容；任意外部网页默认不能调用手机能力。
- Web App 之间默认文件目录和数据库 namespace 隔离。
- Skill 格式必须跟随 Agent Skills / Claude Code 生态，不能为了移动端自定义不兼容格式。
- 对话中的可复用产物必须进入 Artifact Store，不能只存在于消息文本。

## 关键决策

- 第一版本以移动端多模态 Agent 工作台和手机本地能力基座为定位。
- Capability Runtime 是所有能力的统一入口。
- Web 小应用是 Artifact 的高级形态，而不是产品唯一目标。
- Workspace 是组织方式，不是强隔离人格。
- 记忆同时支持全局、Workspace 和会话三个层级。
- Skill 遵循 Agent Skills / Claude Code 当前规范。
- 第一版本不实现远程终端和云端运行时。
- 第一版本不实现语音输入或输出。

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

- 第一版本的真实模型提供方、API Key 管理和模型工具调用协议需要在实现模型接入前确认。
- 图片理解/OCR、PDF 解析和网页搜索的具体 provider 可以随实现阶段选择，但不得改变本规格定义的业务能力。
