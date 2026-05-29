import 'dart:convert';
import 'package:flutter/material.dart';
import '../../domain/capabilities/capability.dart';
import '../../domain/workbench/workbench_store.dart';

class AuditLogPage extends StatefulWidget {
  const AuditLogPage({required this.workbenchStore, super.key});

  final WorkbenchStore workbenchStore;

  @override
  State<AuditLogPage> createState() => _AuditLogPageState();
}

class _AuditLogPageState extends State<AuditLogPage> {
  late Future<List<CapabilityInvocation>> _invocationsFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _invocationsFuture = widget.workbenchStore.loadInvocations().then(
        (list) => list.reversed.toList(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: const Text('操作审计日志'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<List<CapabilityInvocation>>(
        future: _invocationsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data;
          if (data == null || data.isEmpty) {
            return _buildEmptyState();
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: data.length,
            itemBuilder: (context, index) {
              return _InvocationTile(invocation: data[index]);
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            '暂无操作记录',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 8),
          Text(
            'Agent 调用手机能力后，记录会出现在这里。',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }
}

class _InvocationTile extends StatefulWidget {
  const _InvocationTile({required this.invocation});

  final CapabilityInvocation invocation;

  @override
  State<_InvocationTile> createState() => _InvocationTileState();
}

class _InvocationTileState extends State<_InvocationTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final inv = widget.invocation;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _StatusIndicator(status: inv.status),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          inv.capabilityId,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatTime(inv.createdAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey.shade400,
                  ),
                ],
              ),
              if (_expanded) ...[
                const Divider(height: 24),
                _DetailSection(title: '输入参数 (Input)', data: inv.input),
                if (inv.permissionDecision != null) ...[
                  const SizedBox(height: 16),
                  _DetailLabel(
                    title: '权限决策',
                    value: inv.permissionDecision!,
                    isError: inv.permissionDecision == 'denied',
                  ),
                ],
                if (inv.error != null) ...[
                  const SizedBox(height: 16),
                  _DetailSection(
                    title: '错误信息',
                    content: inv.error!,
                    isError: true,
                  ),
                ],
                if (inv.output != null) ...[
                  const SizedBox(height: 16),
                  _DetailSection(title: '执行结果 (Output)', data: inv.output!),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({required this.status});

  final CapabilityInvocationStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (status) {
      CapabilityInvocationStatus.completed => (Colors.green, Icons.check_circle_outline),
      CapabilityInvocationStatus.failed => (Colors.red, Icons.error_outline),
      CapabilityInvocationStatus.denied => (Colors.orange, Icons.block_flipped),
      CapabilityInvocationStatus.pending => (Colors.blue, Icons.hourglass_empty),
      CapabilityInvocationStatus.approved => (Colors.blue, Icons.verified_user_outlined),
    };

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    required this.title,
    this.data,
    this.content,
    this.isError = false,
  });

  final String title;
  final Map<String, Object?>? data;
  final String? content;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final text = content ?? const JsonEncoder.withIndent('  ').convert(data);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFF6B7280),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isError ? Colors.red.shade50 : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isError ? Colors.red.shade100 : Colors.grey.shade200,
            ),
          ),
          child: SelectableText(
            text,
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: isError ? Colors.red.shade800 : Colors.grey.shade800,
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailLabel extends StatelessWidget {
  const _DetailLabel({
    required this.title,
    required this.value,
    this.isError = false,
  });

  final String title;
  final String value;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '$title: ',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFF6B7280),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: isError ? Colors.red.shade50 : Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isError ? Colors.red.shade700 : Colors.blue.shade700,
            ),
          ),
        ),
      ],
    );
  }
}
