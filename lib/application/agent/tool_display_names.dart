String agentToolDisplayName(String name) {
  return switch (name) {
    'project_create_web_app' => '创建 Web App',
    'project_update_web_app' => '更新 Web App',
    'project_test_web_app' => '检查 Web App',
    'artifact_create' => '创建 Artifact',
    'artifact_query' => '查询 Artifact',
    'memory_create' => '写入长期记忆',
    'memory_query' => '查询长期记忆',
    'memory_delete' => '删除长期记忆',
    'db_note_create' => '记录笔记',
    'db_note_query' => '查询笔记',
    'workspace_create' => '创建工作区',
    'workspace_switch' => '切换工作区',
    'file_write_app_file' => '写入文件',
    'file_read_app_file' => '读取文件',
    'file_search_app_files' => '搜索文件',
    'web_search' => '联网搜索',
    'web_fetch' => '读取网页',
    _ => name.replaceAll('_', ' '),
  };
}
