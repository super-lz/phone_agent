import '../../domain/artifacts/artifact.dart';

String buildWebAppFallbackHtml(AgentArtifact webApp) {
  final html = webApp.metadata['html'];
  if (html is String && html.trim().isNotEmpty) {
    return html;
  }
  return '''
<main style="font-family: -apple-system, BlinkMacSystemFont, sans-serif; padding: 24px; line-height: 1.6;">
  <h1>${_escapeHtml(webApp.title)}</h1>
  <p>${_escapeHtml(webApp.summary)}</p>
  <section style="border: 1px solid #e0e0e0; border-radius: 8px; padding: 16px; background: #fff8e1;">
    <h2 style="margin-top: 0; font-size: 18px;">缺少可预览的 Web App 内容</h2>
    <p>这个 Artifact 没有保存 <code>metadata.html</code> 或 <code>content_html</code>，所以无法渲染 AI 生成的真实页面。</p>
    <p>请重新让 AI 创建 Web App；新的工具协议会要求写入完整 HTML、内联 CSS 和内联 JS。</p>
  </section>
</main>
''';
}

String _escapeHtml(String text) {
  return text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
