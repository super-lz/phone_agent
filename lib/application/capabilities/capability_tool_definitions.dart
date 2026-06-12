import 'office_tool_definitions.dart';

class CapabilityToolDefinitions {
  const CapabilityToolDefinitions();

  List<Map<String, Object?>> get all {
    return [
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
              '创建一个可维护的本地 Web 工程并生成可预览 Web App 卡片。用户要求创建小游戏、交互网页、Web App、原型、HTML 页面或“下面给我卡片/能打开体验”时优先使用本工具；必须写入真实项目文件，不能只在正文中说已创建。除极小页面外，默认拆成 index.html、styles.css、app.js 等文件；应优先提供带项目目录的 entry_path，例如 apps/my-game/index.html。若模型只传 index.html 等根路径，系统会自动套入独立项目目录，避免多个 Web App 互相覆盖。需要服务端、数据库或本地文件操作时，使用 server.routes 声明本地 API 路由，前端通过 window.PhoneAgent.serverJson/serverFetch 或 /api 路径调用；当前只在本机 App 内运行，不生成线上部署配置。本工具写入后会自动执行受控静态测试并在输出 test 字段返回结论；test.passed=false 时必须继续修复或向用户说明问题。后续维护时先用 file_search_app_files/file_read_app_file 定位，再用 file_apply_text_patch 修改。默认按手机竖屏设计，适配 360-430px 宽度、触摸操作和安全区域，避免桌面优先布局。需要手机能力时必须遵循 <jsbridge_skill>：声明 permissions，使用 window.PhoneAgent，不要自建或引用 JSBridge SDK。',
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
                          '完整文件内容。入口文件应是完整可运行 HTML，默认移动端竖屏布局；需要 WebView 视口信息时用 window.PhoneAgent.getRuntimeInfo()；需要手机能力时按 <jsbridge_skill> 写防御式调用，通过 window.PhoneAgent.callCapability 或 window.PhoneAgent.getDeviceInfo 等 helper 调用。',
                    },
                  },
                  'required': ['path', 'content'],
                },
              },
              'permissions': {
                'type': 'array',
                'description':
                    'Web App JavaScript 通过 JSBridge 调用的精确 capability id 列表；每一个 window.PhoneAgent 调用都必须在这里声明。',
                'items': {'type': 'string'},
              },
              'database_namespace': {
                'type': 'string',
                'description':
                    '可选。Web App 运行数据数据库 namespace；默认由系统按 workspace + artifactId 生成，通常不要手动填写。',
              },
              'file_namespace': {
                'type': 'string',
                'description':
                    '可选。Web App 运行数据文件 namespace；默认由系统按 workspace + artifactId 生成，通常不要手动填写。',
              },
              'server': _webAppServerSchema(),
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
          'name': 'project_update_web_app',
          'description':
              '维护已有本地 Web App 项目，只更新原项目文件和原 Artifact，不创建新项目或新卡片。用于用户反馈已有网页、小游戏、Web App 的 bug、样式或功能迭代；调用前应先 artifact_query 定位，再读运行日志和项目文件。patches/files 的 path 可以传项目根相对路径（如 index.html、assets/photo.svg），也可以传当前 Workspace 中包含项目根的完整相对路径（如 apps/demo/index.html）；允许新增项目目录内的资源文件，禁止写到项目目录外。本工具写入后会自动执行受控静态测试并在输出 test 字段返回结论；test.passed=false 时必须继续修复或向用户说明问题。',
          'parameters': {
            'type': 'object',
            'properties': {
              'artifact_id': {
                'type': 'string',
                'description': '要更新的 Web App Artifact ID。',
              },
              'summary': {'type': 'string', 'description': '本次更新摘要。'},
              'patches': {
                'type': 'array',
                'description': '对已有项目文件做精确文本替换。',
                'items': {
                  'type': 'object',
                  'properties': {
                    'path': {'type': 'string', 'description': '项目内文件路径。'},
                    'old_text': {'type': 'string', 'description': '要替换的原文。'},
                    'new_text': {'type': 'string', 'description': '替换后的文本。'},
                    'replace_all': {
                      'type': 'boolean',
                      'description': '是否替换全部匹配，默认 false。',
                    },
                  },
                  'required': ['path', 'old_text', 'new_text'],
                },
              },
              'files': {
                'type': 'array',
                'description': '完整写入或新增的项目目录内文件，可用于添加图片、SVG、CSS、JS、HTML 等资源。',
                'items': {
                  'type': 'object',
                  'properties': {
                    'path': {'type': 'string', 'description': '项目内文件路径。'},
                    'content': {'type': 'string', 'description': '完整文件内容。'},
                  },
                  'required': ['path', 'content'],
                },
              },
              'permissions': {
                'type': 'array',
                'description':
                    '可选，更新 Web App manifest 中声明的 capability 权限；新增 window.PhoneAgent 调用时必须同步补充精确 capability id。',
                'items': {'type': 'string'},
              },
              'server': _webAppServerSchema(),
            },
            'required': ['artifact_id'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'project_test_web_app',
          'description':
              '对已有本地 Web App 项目做受控静态复测。project_create_web_app 和 project_update_web_app 已会自动测试并在结果 test 中返回结论；本工具用于用户明确要求复测，或维护已有项目时单独确认当前状态。优先使用 Web App Artifact ID；系统也会尽量识别同 Workspace 内唯一匹配的 projectId、入口目录或项目目录名。当前不执行任意 shell、npm 或网络测试。',
          'parameters': {
            'type': 'object',
            'properties': {
              'artifact_id': {
                'type': 'string',
                'description': '要检查的 Web App Artifact ID。',
              },
            },
            'required': ['artifact_id'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'project_version_history',
          'description': '查询已有 Web App 项目的轻量版本历史。',
          'parameters': {
            'type': 'object',
            'properties': {
              'artifact_id': {
                'type': 'string',
                'description': 'Web App Artifact ID。',
              },
            },
            'required': ['artifact_id'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'project_revert_web_app',
          'description': '把已有 Web App 项目回滚到某个历史版本；回滚后仍更新原 Artifact，不创建新项目或新卡片。',
          'parameters': {
            'type': 'object',
            'properties': {
              'artifact_id': {
                'type': 'string',
                'description': 'Web App Artifact ID。',
              },
              'version': {'type': 'integer', 'description': '要回滚到的历史版本号。'},
              'summary': {'type': 'string', 'description': '本次回滚摘要。'},
            },
            'required': ['artifact_id', 'version'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'artifact_create',
          'description':
              '当产出需要后续复用、作为卡片展示或创建本地 Web App 时，把结果保存为当前 Workspace 的 Artifact。只要用户要求卡片、预览入口、打开体验或本地 Web App，就必须调用本工具，不能只在 Markdown 中输出假链接。创建 web_app 时必须同时提供 content_html，且应包含完整 HTML、内联 CSS 和内联 JS；Web App 默认按手机竖屏设计。如果网页脚本调用 window.PhoneAgent.callCapability 或 JSBridge helper，必须遵循 <jsbridge_skill>，metadata.permissions 必须声明每个精确 capability id。',
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
                    '仅 web_app 使用：完整可运行 HTML 文档或片段，必须包含页面真实内容、样式和交互脚本。优先内联 CSS/JS，避免依赖外部资源。默认移动端竖屏布局，使用 viewport、touch-friendly 控件和安全区域。WebView 视口可用 window.PhoneAgent.getRuntimeInfo()；调用手机能力时按 <jsbridge_skill> 使用 window.PhoneAgent.callCapability 或 helper，例如 await window.PhoneAgent.getDeviceInfo()。',
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
          'description':
              '读取 Web App Artifact 的运行时日志。当 Web App 运行出错、JSBridge 调用失败或用户反馈应用行为异常时，用于查看 console.log 和 window.error 输出。',
          'parameters': {
            'type': 'object',
            'properties': {
              'artifactId': {
                'type': 'string',
                'description': '目标 Artifact ID。',
              },
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
          'name': 'app_info',
          'description':
              '读取当前 Phone Agent 应用本身的信息，例如应用名、包名或 Bundle ID、版本号和构建号。用于用户询问当前安装版本、排障或确认构建来源。',
          'parameters': {'type': 'object', 'properties': <String, Object?>{}},
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
          'name': 'camera_capture_photo',
          'description':
              '打开系统相机拍摄一张照片。只有用户明确要求拍照、采集当前画面或 Web App 需要相机输入时使用；会触发系统 UI，用户可取消。',
          'parameters': {
            'type': 'object',
            'properties': {
              'max_width': {'type': 'number', 'description': '可选，限制图片最大宽度。'},
              'max_height': {'type': 'number', 'description': '可选，限制图片最大高度。'},
              'image_quality': {
                'type': 'integer',
                'description': '可选，图片质量 1-100。',
              },
            },
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'camera_capture_video',
          'description':
              '打开系统相机拍摄一段视频。只有用户明确要求拍视频、录视频或 Web App 需要摄像头视频输入时使用；会触发系统 UI，用户可取消。',
          'parameters': {
            'type': 'object',
            'properties': {
              'max_duration_seconds': {
                'type': 'integer',
                'description': '可选，限制最长拍摄秒数，范围 1-3600。',
              },
            },
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'flashlight_set',
          'description':
              '打开或关闭手机手电筒/闪光灯硬件。只有用户明确要求开灯、关灯、打开手电筒、关闭手电筒、toggle torch 等设备硬件控制时使用；不要用于网页里的视觉闪光效果。',
          'parameters': {
            'type': 'object',
            'properties': {
              'enabled': {
                'type': 'boolean',
                'description': 'true 表示打开手电筒，false 表示关闭手电筒。',
              },
            },
            'required': ['enabled'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'flashlight_status',
          'description': '查询当前手机手电筒/闪光灯硬件是否可用以及是否开启。',
          'parameters': {'type': 'object', 'properties': <String, Object?>{}},
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'media_pick_image',
          'description':
              '打开系统相册选择一张图片。只有用户明确要求从相册选择图片、上传图片或 Web App 需要图片输入时使用；用户可取消。',
          'parameters': {
            'type': 'object',
            'properties': {
              'max_width': {'type': 'number', 'description': '可选，限制图片最大宽度。'},
              'max_height': {'type': 'number', 'description': '可选，限制图片最大高度。'},
              'image_quality': {
                'type': 'integer',
                'description': '可选，图片质量 1-100。',
              },
            },
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'media_pick_images',
          'description':
              '打开系统相册一次选择多张图片。只有用户明确要求多选图片、选择多张照片、批量上传图片、导入一组图片，或 Web App 需要多张图片输入时使用；用户可取消。',
          'parameters': {
            'type': 'object',
            'properties': {
              'max_width': {'type': 'number', 'description': '可选，限制图片最大宽度。'},
              'max_height': {'type': 'number', 'description': '可选，限制图片最大高度。'},
              'image_quality': {
                'type': 'integer',
                'description': '可选，图片质量 1-100。',
              },
            },
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'audio_record_start',
          'description':
              '开始通过麦克风录音。只有用户明确要求开始录音、录一段声音、采集语音或 Web App 需要麦克风音频输入时使用；同一时间只允许一个录音会话。',
          'parameters': {'type': 'object', 'properties': <String, Object?>{}},
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'audio_record_stop',
          'description': '停止当前麦克风录音并返回音频文件元数据。只有存在用户语义上的停止录音、结束录音或完成录音请求时使用。',
          'parameters': {'type': 'object', 'properties': <String, Object?>{}},
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'audio_record_cancel',
          'description': '取消当前麦克风录音并丢弃录音文件。只有用户明确要求取消录音或放弃当前录音时使用。',
          'parameters': {'type': 'object', 'properties': <String, Object?>{}},
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'contacts_pick',
          'description':
              '打开系统联系人选择器，让用户选择一个联系人，并返回被选中联系人的姓名、电话和邮箱。只有用户明确要求选择联系人、从通讯录导入联系人或 Web App 需要联系人输入时使用；不会读取完整通讯录。',
          'parameters': {'type': 'object', 'properties': <String, Object?>{}},
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'barcode_scan_camera',
          'description':
              '打开系统相机拍摄一张包含二维码或条码的图片，并在本地解析码值。只有用户明确要求扫描二维码、扫码、扫条码或 Web App 需要扫码输入时使用；用户可取消。',
          'parameters': {
            'type': 'object',
            'properties': {
              'formats': {
                'type': 'array',
                'description':
                    '可选，限制识别格式，例如 qr_code、ean13、code128、data_matrix。',
                'items': {'type': 'string'},
              },
            },
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'barcode_scan_image',
          'description':
              '从相册选择一张包含二维码或条码的图片，并在本地解析码值。用于用户明确要求识别截图、相册图片里的二维码或条码时使用；用户可取消。',
          'parameters': {
            'type': 'object',
            'properties': {
              'formats': {
                'type': 'array',
                'description':
                    '可选，限制识别格式，例如 qr_code、ean13、code128、data_matrix。',
                'items': {'type': 'string'},
              },
            },
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'media_pick_video',
          'description':
              '打开系统相册选择一个视频。只有用户明确要求选择视频、上传视频或 Web App 需要视频输入时使用；用户可取消。',
          'parameters': {'type': 'object', 'properties': <String, Object?>{}},
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'file_pick_system_file',
          'description':
              '打开系统文件选择器选择一个本机文件。用于用户明确要求从手机文件系统导入、选择或上传文件时使用；只返回被用户选择的文件元数据和本地 URI。',
          'parameters': {
            'type': 'object',
            'properties': {
              'allowed_extensions': {
                'type': 'array',
                'description': '可选，限制扩展名，例如 pdf、docx、xlsx。',
                'items': {'type': 'string'},
              },
            },
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
          'name': 'system_volume_set',
          'description':
              '设置当前设备媒体/当前输出音量。适合用户明确要求调高、调低、静音或设置媒体音量时使用；平台不允许静默设置时必须返回结构化 unsupported。',
          'parameters': {
            'type': 'object',
            'properties': {
              'level': {
                'type': 'number',
                'description': '媒体音量比例，范围 0 到 1；0 静音，1 最大。',
              },
            },
            'required': ['level'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'system_volume_status',
          'description': '查询当前设备媒体/当前输出音量，以及当前平台是否支持静默设置音量。',
          'parameters': {'type': 'object', 'properties': <String, Object?>{}},
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'system_ui_set',
          'description':
              '设置当前应用的系统 UI 显示模式。适合用户明确要求全屏、沉浸式、显示/隐藏状态栏导航栏，或本地 Web App/游戏/演示需要沉浸显示时使用。',
          'parameters': {
            'type': 'object',
            'properties': {
              'mode': {
                'type': 'string',
                'description':
                    '显示模式：normal、fullscreen、edge_to_edge、lean_back、immersive、immersive_sticky。',
              },
            },
            'required': ['mode'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'system_ui_status',
          'description': '查询当前应用的系统 UI 显示模式和状态栏/导航栏显示状态。',
          'parameters': {'type': 'object', 'properties': <String, Object?>{}},
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
          'name': 'screen_brightness_set',
          'description':
              '设置当前应用/当前屏幕亮度。适合用户明确要求调亮、调暗、设置屏幕亮度，或本地 Web App/演示需要临时调整亮度时使用；不承诺修改系统全局永久亮度。',
          'parameters': {
            'type': 'object',
            'properties': {
              'level': {
                'type': 'number',
                'description': '亮度比例，范围 0 到 1；0 最暗，1 最亮。',
              },
            },
            'required': ['level'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'screen_brightness_status',
          'description': '查询当前应用/当前屏幕亮度状态和是否使用系统默认亮度。',
          'parameters': {'type': 'object', 'properties': <String, Object?>{}},
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'screen_metrics',
          'description':
              '读取当前屏幕和 Flutter View 的尺寸、像素比、安全区、键盘 inset、亮暗模式、语言环境和文字缩放等显示指标。用于排版适配、Web App 调试或用户询问屏幕尺寸时使用。',
          'parameters': {'type': 'object', 'properties': <String, Object?>{}},
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'screen_orientation_set',
          'description':
              '设置当前应用的屏幕方向偏好。适合用户明确要求横屏、竖屏、解锁自动旋转，或本地 Web App/演示需要固定方向时使用。',
          'parameters': {
            'type': 'object',
            'properties': {
              'mode': {
                'type': 'string',
                'description':
                    '方向模式：unlocked、portrait、portrait_up、portrait_down、landscape、landscape_left、landscape_right。',
              },
            },
            'required': ['mode'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'screen_orientation_status',
          'description': '查询当前应用的屏幕方向锁定状态和首选方向。',
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
          'name': 'notification_pending',
          'description':
              '查看 Phone Agent 已安排但尚未触发的本地通知列表。用于用户询问还有哪些提醒、待提醒或通知安排时使用。',
          'parameters': {'type': 'object', 'properties': <String, Object?>{}},
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'notification_cancel',
          'description':
              '取消指定 ID 的本地通知。用于用户明确要求取消某条提醒，并且上下文中有 notification_id 时使用。',
          'parameters': {
            'type': 'object',
            'properties': {
              'notification_id': {
                'type': 'integer',
                'description': '要取消的本地通知 ID。',
              },
            },
            'required': ['notification_id'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'notification_cancel_all',
          'description':
              '取消 Phone Agent 安排的全部待触发本地通知。只有用户明确要求清空、取消全部提醒或删除所有通知安排时使用。',
          'parameters': {'type': 'object', 'properties': <String, Object?>{}},
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

  static Map<String, Object?> _webAppServerSchema() {
    return {
      'type': 'object',
      'description':
          '可选。本地全栈 Web App 的声明式服务端配置。运行时只在 App 内本机回环地址启动，不执行任意 Node/Dart/shell，不生成线上部署。需要服务端逻辑时优先把 handlerPath 指向项目内 JSON handler 文件。',
      'properties': {
        'routes': {
          'type': 'array',
          'description':
              '本地 API 路由。前端用 window.PhoneAgent.serverJson/serverFetch 或 /api 路径调用。',
          'items': {
            'type': 'object',
            'properties': {
              'method': {
                'type': 'string',
                'description': 'GET、POST、PUT、PATCH 或 DELETE。',
              },
              'path': {
                'type': 'string',
                'description': '必须以 /api/ 开头，例如 /api/notes。',
              },
              'capability': {
                'type': 'string',
                'description':
                    '该路由调用的 capability id，例如 db.note.query、db.note.create、file.read_app_file 或 file.write_app_file；必须同步声明到 permissions。',
              },
              'handlerPath': {
                'type': 'string',
                'description':
                    '可选。项目内服务端 handler JSON 文件路径，例如 server/create-note.json；路径相对 Web App 项目根目录。',
              },
              'handler': {
                'type': 'object',
                'description':
                    '可选。内联 server action handler。更推荐使用 handlerPath 写入独立项目文件。handler.steps 顺序调用 capability，handler.response 用 \$request.xxx 和 \$steps.stepId.output.xxx 模板生成响应。',
              },
              'input': {
                'type': 'object',
                'description': '可选固定输入，会与 query 参数或 JSON body 合并；请求输入优先级更高。',
              },
            },
            'required': ['method', 'path'],
          },
        },
      },
    };
  }
}
