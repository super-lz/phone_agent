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
            },
            'required': ['path'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'artifact_create',
          'description':
              '当产出需要后续复用、作为卡片展示或创建本地 Web App 时，把结果保存为当前 Workspace 的 Artifact。',
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
              'metadata': {
                'type': 'object',
                'description': '可选元数据，例如 Web App 的 entry 和 permissions。',
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
          'name': 'device_info',
          'description': '读取当前手机或模拟器的基础设备信息，用于排障、适配判断或环境说明。',
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
          'name': 'location_get_current',
          'description': '当用户明确要求基于当前位置处理问题时，获取当前设备位置。',
          'parameters': {'type': 'object', 'properties': <String, Object?>{}},
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'notification_schedule',
          'description': '当用户明确要求稍后提醒或安排本地通知时，创建一条系统通知。',
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
    ];
  }
}
