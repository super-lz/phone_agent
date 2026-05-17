import 'dart:convert';

import '../../data/models/openai_compatible_chat_client.dart';

class ToolCallAccumulator {
  final Map<int, _ToolCallBuffer> _buffers = {};

  void applyAll(List<ToolCallDelta> deltas) {
    for (final delta in deltas) {
      final buffer = _buffers.putIfAbsent(
        delta.index,
        () => _ToolCallBuffer(index: delta.index),
      );
      buffer.apply(delta);
    }
  }

  List<ToolCallRequest> toRequests() {
    final entries = _buffers.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    return entries
        .map((entry) => entry.value.toRequest())
        .whereType<ToolCallRequest>()
        .toList(growable: false);
  }
}

class _ToolCallBuffer {
  _ToolCallBuffer({required this.index});

  final int index;
  final StringBuffer argumentsBuffer = StringBuffer();
  String? id;
  String? name;

  void apply(ToolCallDelta delta) {
    id ??= delta.id;
    name ??= delta.name;
    final argumentsDelta = delta.argumentsDelta;
    if (argumentsDelta != null) {
      argumentsBuffer.write(argumentsDelta);
    }
  }

  ToolCallRequest? toRequest() {
    final requestName = name;
    if (requestName == null || requestName.trim().isEmpty) {
      return null;
    }
    return ToolCallRequest(
      id: id ?? 'call_${DateTime.now().microsecondsSinceEpoch}_$index',
      name: requestName,
      arguments: _decodeArguments(argumentsBuffer.toString()),
    );
  }

  Map<String, Object?> _decodeArguments(String rawArguments) {
    if (rawArguments.trim().isEmpty) {
      return const {};
    }
    try {
      final Object? decoded = jsonDecode(rawArguments);
      if (decoded is Map<String, Object?>) {
        return decoded;
      }
    } on FormatException {
      return {'_rawArguments': rawArguments, '_parseError': 'invalid_json'};
    }
    return {'_rawArguments': rawArguments};
  }
}
