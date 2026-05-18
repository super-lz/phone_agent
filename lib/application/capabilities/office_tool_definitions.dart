const officeToolDefinitions = <Map<String, Object?>>[
  {
    'type': 'function',
    'function': {
      'name': 'document_extract',
      'description':
          '从当前 Workspace 文件中提取 Word/docx、Markdown、HTML、TXT 等文档文本，用于总结、问答和审阅。',
      'parameters': {
        'type': 'object',
        'properties': {
          'path': {'type': 'string', 'description': '当前 Workspace 文件区内的相对路径。'},
          'max_chars': {'type': 'integer', 'description': '最多返回字符数，默认 12000。'},
        },
        'required': ['path'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'document_generate',
      'description':
          '生成新的 docx、pdf、html、md 或 txt 文档文件。第一版生成可导出文件，不承诺完整 Office 编辑器体验。',
      'parameters': {
        'type': 'object',
        'properties': {
          'title': {'type': 'string', 'description': '文档标题。'},
          'body': {'type': 'string', 'description': '文档正文。'},
          'format': {
            'type': 'string',
            'description': 'docx、pdf、html、md 或 txt，默认 docx。',
          },
          'path': {'type': 'string', 'description': '输出相对路径。'},
        },
        'required': ['body'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'document_apply_text_patch',
      'description': '对文档提取出的文本做受控局部替换，并生成新的 docx 或 pdf 文件。该能力不保留复杂原格式。',
      'parameters': {
        'type': 'object',
        'properties': {
          'path': {'type': 'string', 'description': '要修改的文档相对路径。'},
          'old_text': {'type': 'string', 'description': '要替换的原文，默认必须唯一。'},
          'new_text': {'type': 'string', 'description': '替换后的文本。'},
          'output_path': {
            'type': 'string',
            'description': '可选输出路径，默认生成 patched 文件。',
          },
          'replace_all': {'type': 'boolean', 'description': '是否替换所有匹配项。'},
        },
        'required': ['path', 'old_text', 'new_text'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'spreadsheet_extract',
      'description': '从 xlsx 或 csv 表格中提取文本，用于财报、数据表和清单分析。',
      'parameters': {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': '当前 Workspace 文件区内的表格相对路径。',
          },
          'max_chars': {'type': 'integer', 'description': '最多返回字符数，默认 12000。'},
        },
        'required': ['path'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'spreadsheet_generate',
      'description': '根据二维 rows 生成 xlsx 或 csv 表格文件。',
      'parameters': {
        'type': 'object',
        'properties': {
          'title': {'type': 'string', 'description': '表格标题。'},
          'format': {'type': 'string', 'description': 'xlsx 或 csv，默认 xlsx。'},
          'path': {'type': 'string', 'description': '输出相对路径。'},
          'rows': {
            'type': 'array',
            'description': '二维数组，每个内部数组是一行。',
            'items': {
              'type': 'array',
              'items': {'type': 'string'},
            },
          },
        },
        'required': ['rows'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'presentation_extract',
      'description': '从 pptx、md 或 html 演示文稿中提取文本，用于总结和审阅。',
      'parameters': {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': '当前 Workspace 文件区内的演示文件相对路径。',
          },
          'max_chars': {'type': 'integer', 'description': '最多返回字符数，默认 12000。'},
        },
        'required': ['path'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'presentation_generate',
      'description': '根据 slides 生成 pptx、md 或 html 演示文稿。',
      'parameters': {
        'type': 'object',
        'properties': {
          'title': {'type': 'string', 'description': '演示文稿标题。'},
          'format': {
            'type': 'string',
            'description': 'pptx、md 或 html，默认 pptx。',
          },
          'path': {'type': 'string', 'description': '输出相对路径。'},
          'slides': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'title': {'type': 'string'},
                'bullets': {
                  'type': 'array',
                  'items': {'type': 'string'},
                },
                'body': {'type': 'string'},
              },
            },
          },
        },
        'required': ['slides'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'pdf_extract',
      'description': '从 PDF 文件中提取可识别文本。第一版对扫描版 PDF 不做 OCR。',
      'parameters': {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': '当前 Workspace 文件区内的 PDF 相对路径。',
          },
          'max_chars': {'type': 'integer', 'description': '最多返回字符数，默认 12000。'},
        },
        'required': ['path'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'pdf_generate',
      'description': '根据标题和正文生成一个可导出的 PDF 文件。',
      'parameters': {
        'type': 'object',
        'properties': {
          'title': {'type': 'string', 'description': 'PDF 标题。'},
          'body': {'type': 'string', 'description': 'PDF 正文。'},
          'path': {'type': 'string', 'description': '输出相对路径。'},
        },
        'required': ['body'],
      },
    },
  },
];
