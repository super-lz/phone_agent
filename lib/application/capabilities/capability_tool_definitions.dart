import 'office_tool_definitions.dart';

class CapabilityToolDefinitions {
  const CapabilityToolDefinitions();

  List<Map<String, Object?>> get all {
    return const [
      {
        'type': 'function',
        'function': {
          'name': 'memory_create',
          'description': '当用户明确要求记住长期偏好、事实或规则时使用。长期记忆是全局的，不按 Workspace 切分。',
          'parameters': {
            'type': 'object',
            'properties': {
              'content': {'type': 'string', 'description': '需要记住的内容。'},
            },
            'required': ['content'],
          },
        },
      },
      ...officeToolDefinitions,
      {
        'type': 'function',
        'function': {
          'name': 'db_note_create',
          'description': '把用户要求记录、沉淀或稍后复用的信息写入当前 Workspace 的本地 Note。',
          'parameters': {
            'type': 'object',
            'properties': {
              'title': {'type': 'string', 'description': '笔记标题，可省略。'},
              'content': {'type': 'string', 'description': '笔记正文。'},
            },
            'required': ['content'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'db_note_query',
          'description': '查询当前 Workspace 中已经保存的本地 Note。',
          'parameters': {
            'type': 'object',
            'properties': {
              'query': {'type': 'string', 'description': '查询关键词，可为空。'},
            },
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'memory_query',
          'description':
              '当用户询问系统记住了什么，或需要盘点/管理大量长期记忆时使用。普通回答会自动获得长期记忆，不需要先调用本工具。',
          'parameters': {
            'type': 'object',
            'properties': {
              'query': {'type': 'string', 'description': '要查询的关键词，可为空。'},
            },
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'memory_delete',
          'description': '当用户明确要求忘记某条已保存记忆时使用。',
          'parameters': {
            'type': 'object',
            'properties': {
              'memory_id': {'type': 'string', 'description': '要删除的记忆 ID。'},
            },
            'required': ['memory_id'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'file_write_app_file',
          'description': '把文本内容写入当前 Workspace 的应用沙箱文件。只能使用相对路径，不能访问系统任意路径。',
          'parameters': {
            'type': 'object',
            'properties': {
              'path': {
                'type': 'string',
                'description': '当前 Workspace 文件区内的相对路径，例如 notes/summary.md。',
              },
              'content': {'type': 'string', 'description': '要写入的文本内容。'},
              'overwrite': {
                'type': 'boolean',
                'description': '是否覆盖已有文件，默认 true。',
              },
            },
            'required': ['path', 'content'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'file_read_app_file',
          'description': '读取当前 Workspace 应用沙箱内的文本文件。不能读取其它 Workspace 或系统文件。',
          'parameters': {
            'type': 'object',
            'properties': {
              'path': {
                'type': 'string',
                'description': '当前 Workspace 文件区内的相对路径。',
              },
              'max_chars': {
                'type': 'integer',
                'description': '最多返回字符数，默认 12000。',
              },
              'start_line': {
                'type': 'integer',
                'description': '可选，按 1 开始的起始行号；用于只读取文件局部片段。',
              },
              'line_count': {
                'type': 'integer',
                'description': '可选，读取多少行；配合 start_line 使用，默认 120。',
              },
            },
            'required': ['path'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'file_search_app_files',
          'description':
              '在当前 Workspace 应用沙箱文件中搜索关键词，返回带行号的片段。用于定位项目 bug、查找特定文件里的具体问题或决定下一步读取哪个行范围。',
          'parameters': {
            'type': 'object',
            'properties': {
              'query': {'type': 'string', 'description': '要搜索的关键词。'},
              'path': {'type': 'string', 'description': '可选，限制只搜索某个相对文件路径。'},
              'path_prefix': {
                'type': 'string',
                'description': '可选，限制只搜索某个项目目录前缀。',
              },
              'max_results': {
                'type': 'integer',
                'description': '最多返回多少条结果，默认 20。',
              },
              'context_lines': {
                'type': 'integer',
                'description': '每条命中前后附带多少行上下文，默认 2。',
              },
            },
            'required': ['query'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'file_apply_text_patch',
          'description':
              '对当前 Workspace 应用沙箱内的文本文件做精确补丁修改。用于维护 AI 已生成的项目文件，必须提供能唯一匹配的 old_text，避免整文件覆盖。',
          'parameters': {
            'type': 'object',
            'properties': {
              'path': {
                'type': 'string',
                'description': '当前 Workspace 文件区内的相对路径。',
              },
              'old_text': {
                'type': 'string',
                'description': '要被替换的原文，默认必须在文件中唯一出现。',
              },
              'new_text': {'type': 'string', 'description': '替换后的新文本。'},
              'replace_all': {
                'type': 'boolean',
                'description': '是否替换所有匹配项，默认 false。',
              },
            },
            'required': ['path', 'old_text', 'new_text'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'project_create_web_app',
          'description':
              '创建一个可维护的本地 Web 工程并生成可预览 Web App 卡片。用户要求创建小游戏、交互网页、Web App、原型、HTML 页面或“下面给我卡片/能打开体验”时优先使用本工具；必须写入真实项目文件，不能只在正文中说已创建。除极小页面外，默认拆成 index.html、styles.css、app.js 等文件，后续维护时先用 file_search_app_files/file_read_app_file 定位，再用 file_apply_text_patch 修改。默认按手机竖屏设计，适配 360-430px 宽度、触摸操作和安全区域，避免桌面优先布局。',
          'parameters': {
            'type': 'object',
            'properties': {
              'title': {'type': 'string', 'description': '项目/Artifact 标题。'},
              'summary': {'type': 'string', 'description': '项目摘要。'},
              'entry_path': {
                'type': 'string',
                'description': '入口 HTML 文件相对路径，例如 games/gold-miner/index.html。',
              },
              'files': {
                'type': 'array',
                'description': '要写入当前 Workspace 文件区的项目文件。',
                'items': {
                  'type': 'object',
                  'properties': {
                    'path': {
                      'type': 'string',
                      'description': '相对路径，不能是绝对路径或包含 ..。',
                    },
                    'content': {
                      'type': 'string',
                      'description':
                          '完整文件内容。入口文件应是完整可运行 HTML，默认移动端竖屏布局；需要 WebView 视口信息时用 window.PhoneAgent.getRuntimeInfo()，需要手机能力时通过 window.PhoneAgent.callCapability 或 window.PhoneAgent.getDeviceInfo 等 JSBridge helper 调用。',
                    },
                  },
                  'required': ['path', 'content'],
                },
              },
              'permissions': {
                'type': 'array',
                'description': 'Web App 需要通过 JSBridge 调用的 capability id 列表。',
                'items': {'type': 'string'},
              },
              'metadata': {
                'type': 'object',
                'description': '额外元数据，例如 tags、kind、framework。',
              },
            },
            'required': ['title', 'summary', 'files'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'artifact_create',
          'description':
              '当产出需要后续复用、作为卡片展示或创建本地 Web App 时，把结果保存为当前 Workspace 的 Artifact。只要用户要求卡片、预览入口、打开体验或本地 Web App，就必须调用本工具，不能只在 Markdown 中输出假链接。创建 web_app 时必须同时提供 content_html，且应包含完整 HTML、内联 CSS 和内联 JS；Web App 默认按手机竖屏设计。如果网页脚本调用 window.PhoneAgent.callCapability 或 JSBridge helper，metadata.permissions 必须声明每个精确 capability id。',
          'parameters': {
            'type': 'object',
            'properties': {
              'type': {
                'type': 'string',
                'description':
                    'Artifact 类型：document、image、table、report、note、task_list、file、web_app。',
              },
              'title': {'type': 'string', 'description': 'Artifact 标题。'},
              'summary': {'type': 'string', 'description': 'Artifact 摘要。'},
              'content_html': {
                'type': 'string',
                'description':
                    '仅 web_app 使用：完整可运行 HTML 文档或片段，必须包含页面真实内容、样式和交互脚本。优先内联 CSS/JS，避免依赖外部资源。默认移动端竖屏布局，使用 viewport、touch-friendly 控件和安全区域。WebView 视口可用 window.PhoneAgent.getRuntimeInfo()；调用手机能力时使用 window.PhoneAgent.callCapability 或 helper，例如 await window.PhoneAgent.getDeviceInfo()。',
              },
              'metadata': {
                'type': 'object',
                'description':
                    '可选元数据。Web App 可声明 entry、permissions；也兼容 metadata.html，但优先使用 content_html。permissions 示例：["device.info","db.note.create","file.write_app_file","time.get_current","web.search"]。',
              },
            },
            'required': ['title', 'summary'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'artifact_query',
          'description': '查询当前 Workspace 已保存的 Artifact，用于引用已有产物。',
          'parameters': {
            'type': 'object',
            'properties': {
              'query': {'type': 'string', 'description': '查询关键词，可为空。'},
              'type': {'type': 'string', 'description': '可选 Artifact 类型过滤。'},
            },
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'artifact_inspect_logs',
          'description': '读取 Web App Artifact 的运行时日志。当 Web App 运行出错、JSBridge 调用失败或用户反馈应用行为异常时，用于查看 console.log 和 window.error 输出。',
          'parameters': {
            'type': 'object',
            'properties': {
              'artifactId': {'type': 'string', 'description': '目标 Artifact ID。'},
              'max_lines': {
                'type': 'integer',
                'description': '最多返回多少行日志，默认 50。',
              },
            },
            'required': ['artifactId'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'workspace_create',
          'description': '当用户明确要求新建工作区时，创建一个 Workspace 并切换过去。',
          'parameters': {
            'type': 'object',
            'properties': {
              'name': {'type': 'string', 'description': '工作区名称。'},
              'description': {'type': 'string', 'description': '工作区用途说明，可省略。'},
            },
            'required': ['name'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'workspace_switch',
          'description': '当用户明确要求切换工作区时，按工作区 ID 或名称切换当前 Workspace。',
          'parameters': {
            'type': 'object',
            'properties': {
              'workspace_id': {
                'type': 'string',
                'description': '目标工作区 ID。若不知道 ID，可使用 name。',
              },
              'name': {'type': 'string', 'description': '目标工作区名称。'},
            },
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'device_info',
          'description': '读取当前手机或模拟器的基础设备信息，用于排障、适配判断或环境说明。',
          'parameters': {'type': 'object', 'properties': <String, Object?>{}},
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'time_get_current',
          'description':
              '读取设备当前本地时间、UTC 时间和时区偏移。用户询问当前时间，或安排通知/日历前需要校准相对时间时使用。',
          'parameters': {'type': 'object', 'properties': <String, Object?>{}},
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'clipboard_read',
          'description': '读取系统剪贴板中的纯文本内容。只有当用户明确要求读取剪贴板时才使用。',
          'parameters': {'type': 'object', 'properties': <String, Object?>{}},
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'battery_status',
          'description': '读取当前设备电池电量、充电状态和省电模式。用于续航判断、长任务前检查或 Web App 适配。',
          'parameters': {'type': 'object', 'properties': <String, Object?>{}},
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'network_status',
          'description':
              '读取当前设备网络连接类型，例如 Wi-Fi、蜂窝、VPN 或无连接。该能力只表示连接类型，不保证外网一定可达。',
          'parameters': {'type': 'object', 'properties': <String, Object?>{}},
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'clipboard_write',
          'description': '把用户明确要求复制的文本写入系统剪贴板。',
          'parameters': {
            'type': 'object',
            'properties': {
              'text': {'type': 'string', 'description': '要写入剪贴板的文本。'},
            },
            'required': ['text'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'share_text',
          'description':
              '打开系统分享面板，把用户明确要求分享的文本交给其它 App。该能力会触发系统 UI，需要用户自己选择目标应用。',
          'parameters': {
            'type': 'object',
            'properties': {
              'text': {'type': 'string', 'description': '要分享的文本。'},
              'subject': {'type': 'string', 'description': '可选分享主题。'},
            },
            'required': ['text'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'system_haptic_feedback',
          'description': '触发一次系统触感反馈，用于用户明确要求震动、触感提示或 Web App 交互反馈。',
          'parameters': {
            'type': 'object',
            'properties': {
              'type': {
                'type': 'string',
                'description':
                    '触感类型：light、medium、heavy、selection、vibrate，默认 light。',
              },
            },
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'system_sound_alert',
          'description': '播放一次系统提示音。只在用户明确要求提示音、点击音或提醒反馈时使用。',
          'parameters': {
            'type': 'object',
            'properties': {
              'type': {
                'type': 'string',
                'description': '声音类型：alert 或 click，默认 alert。',
              },
            },
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'permission_open_settings',
          'description': '打开系统应用设置页，帮助用户手动开启定位、通知等权限。只有用户要求处理权限时使用。',
          'parameters': {'type': 'object', 'properties': <String, Object?>{}},
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'url_open_external',
          'description':
              '使用系统能力打开外部 URL。仅支持 http、https、mailto、tel、sms 和 geo scheme，会跳出当前应用或打开系统 UI。',
          'parameters': {
            'type': 'object',
            'properties': {
              'url': {'type': 'string', 'description': '要打开的完整 URL。'},
            },
            'required': ['url'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'screen_keep_awake',
          'description': '设置当前应用运行时是否保持屏幕常亮。适合用户明确要求长时间显示、计时器或演示场景。',
          'parameters': {
            'type': 'object',
            'properties': {
              'enabled': {
                'type': 'boolean',
                'description': 'true 表示保持屏幕常亮，false 表示恢复系统默认熄屏策略。',
              },
            },
            'required': ['enabled'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'screen_keep_awake_status',
          'description': '查询当前应用是否正在保持屏幕常亮。',
          'parameters': {'type': 'object', 'properties': <String, Object?>{}},
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'sensor_accelerometer_read',
          'description':
              '读取一次设备加速度计数据，返回 x/y/z。用于用户要求检测姿态、运动或 Web App 需要传感器输入时。',
          'parameters': {'type': 'object', 'properties': <String, Object?>{}},
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'sensor_gyroscope_read',
          'description': '读取一次设备陀螺仪数据，返回 x/y/z。用于用户要求检测旋转、姿态变化或交互控制时。',
          'parameters': {'type': 'object', 'properties': <String, Object?>{}},
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'sensor_magnetometer_read',
          'description': '读取一次设备磁力计数据，返回 x/y/z。用于用户要求方向、罗盘或磁场相关信息时。',
          'parameters': {'type': 'object', 'properties': <String, Object?>{}},
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'location_get_current',
          'description': '当用户明确要求基于当前位置处理问题时，获取当前设备位置。',
          'parameters': {'type': 'object', 'properties': <String, Object?>{}},
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'notification_schedule',
          'description': '当用户明确要求稍后提醒或安排本地通知时，创建一条本地通知。它不是系统时钟闹钟，也不会写入日历。',
          'parameters': {
            'type': 'object',
            'properties': {
              'title': {'type': 'string', 'description': '通知标题。'},
              'body': {'type': 'string', 'description': '通知正文。'},
              'delay_seconds': {
                'type': 'number',
                'description': '从现在开始延迟多少秒提醒。未提供 scheduled_at 时默认 60 秒。',
              },
              'scheduled_at': {
                'type': 'string',
                'description': 'ISO 8601 时间。若提供，优先于 delay_seconds。',
              },
            },
            'required': ['title', 'body'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'calendar_event_create',
          'description': '当用户明确要求加入日历、创建日程、安排会议或保存日历事件时，打开系统日历添加事件界面，由用户确认保存。',
          'parameters': {
            'type': 'object',
            'properties': {
              'title': {'type': 'string', 'description': '日历事件标题。'},
              'description': {'type': 'string', 'description': '事件说明，可省略。'},
              'location': {'type': 'string', 'description': '地点，可省略。'},
              'start_at': {
                'type': 'string',
                'description': '事件开始时间，ISO 8601 格式。',
              },
              'end_at': {
                'type': 'string',
                'description': '事件结束时间，ISO 8601 格式。若省略，使用 duration_minutes。',
              },
              'duration_minutes': {
                'type': 'integer',
                'description': '事件持续分钟数。未提供 end_at 时默认 60 分钟。',
              },
              'all_day': {'type': 'boolean', 'description': '是否全天事件。'},
            },
            'required': ['title', 'start_at'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'web_search',
          'description': '当用户需要最新信息、外部资料或网页来源时搜索互联网。',
          'parameters': {
            'type': 'object',
            'properties': {
              'query': {'type': 'string', 'description': '搜索关键词。'},
              'max_results': {
                'type': 'integer',
                'description': '最多返回结果数，默认 5。',
              },
            },
            'required': ['query'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'web_fetch',
          'description': '读取指定 URL 的正文，并转换为适合模型理解的文本。',
          'parameters': {
            'type': 'object',
            'properties': {
              'url': {'type': 'string', 'description': '需要读取的网页 URL。'},
              'max_chars': {
                'type': 'integer',
                'description': '最多返回字符数，默认 12000。',
              },
            },
            'required': ['url'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'skill_install',
          'description': '从本地目录安装并索引 Agent Skill。脚本执行仍必须走 Capability Runtime。',
          'parameters': {
            'type': 'object',
            'properties': {
              'source': {
                'type': 'string',
                'description': '本地 Skill 目录路径；zip 和 Git URL 会返回当前不可用原因。',
              },
            },
            'required': ['source'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'skill_invoke',
          'description': '调用已安装的 Agent Skill。',
          'parameters': {
            'type': 'object',
            'properties': {
              'skill_id': {'type': 'string', 'description': '要调用的 Skill ID。'},
              'input': {'type': 'object', 'description': '传递给脚本的参数对象。'},
              'script': {'type': 'string', 'description': '可选：直接提供脚本执行，不推荐。'},
            },
            'required': ['skill_id'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'mcp_connect',
          'description': '保存并测试 HTTP/SSE MCP 连接配置；失败时返回可读原因。',
          'parameters': {
            'type': 'object',
            'properties': {
              'url': {'type': 'string', 'description': 'HTTP/SSE MCP 服务 URL。'},
              'transport': {
                'type': 'string',
                'description': 'http 或 sse。stdio 当前仅保留扩展入口。',
              },
            },
            'required': ['url'],
          },
        },
      },
    ];
  }
}
