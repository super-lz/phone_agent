# 项目结构说明

本文是给开发者和 Agent 快速定位代码的附录，不作为业务实现规格。

项目结构遵循 Flutter 官方推荐的分层思路：UI 层、Data 层，以及本项目需要的应用编排层和 Domain 模型层。

## 顶层目录

```text
lib/
  app/            App 根组件、主题和路由装配
  application/    Agent、Capability 等跨 UI 和 Data 的应用编排
  core/           日志、通用基础设施和与业务无关的横切工具
  data/           外部服务、本地存储、平台插件和数据源实现
  domain/         业务模型、枚举、接口和跨层稳定语义
  features/       用户可见功能页面、View、Controller/ViewModel 和 Widgets
  main.dart       Flutter 启动入口和生产依赖装配
```

## 边界规则

- `features/` 只承载用户可见功能的 UI 组合、页面状态和交互事件，不直接实现模型 API、SQLite、WebSearch 或 Capability 执行细节。
- `application/` 承载应用级编排，例如 Agent Loop、工具调用预算、会话上下文压缩和 Capability Runtime。
- `data/` 承载具体数据源和外部系统适配，例如 OpenAI 兼容模型客户端、API Key Store、WebSearch adapter、SQLite Note Store。
- `domain/` 只放稳定业务类型和接口，例如 MessageBlock、AgentMemory、AgentNote、AgentNoteStore、PermissionPolicy。
- `core/` 只放横切基础能力，例如日志；如果代码依赖业务模型，通常不应放进 `core/`。

## 当前主要路径

```text
lib/application/agent/             Agent Loop、工具调用累积、会话上下文压缩
lib/application/capabilities/      Capability Runtime、工具 schema 和分能力 handler
lib/data/bootstrap/                原型默认数据
lib/data/capabilities/             联网搜索和网页读取 adapter
lib/data/models/                   模型 API Key 和 OpenAI 兼容客户端
lib/data/notes/                    SQLite Note Store
lib/features/settings/             模型设置页
lib/features/workbench/            主工作台 UI
```

## 新代码放置判断

- 新增一个手机能力 adapter：优先放 `lib/data/<capability-area>/`，并通过 `application/capabilities` 注册或调用。
- 新增一个 Capability 执行分支：优先在 `lib/application/capabilities/` 下新增或扩展对应 handler，不把实现细节堆回 `capability_runtime.dart`。
- 新增一个 Agent 编排行为：放 `lib/application/agent/`。
- 新增一个业务概念或接口：放 `lib/domain/<bounded-context>/`。
- 新增一个页面或面板：放 `lib/features/<feature>/`。
- 新增一个跨业务通用工具：只有不依赖业务模型时才放 `lib/core/`。
