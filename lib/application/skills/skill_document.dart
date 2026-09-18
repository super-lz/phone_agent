import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Parsed, portable form of a standard Agent Skill document.
///
/// A Skill is instructions and optional package resources. It is intentionally
/// separate from any executable adapter: loading a document must never grant
/// permission to execute a script or an underlying capability.
class SkillDocument {
  const SkillDocument({
    required this.name,
    required this.description,
    required this.instructions,
    required this.rootPath,
    required this.manifestPath,
  });

  final String name;
  final String description;
  final String instructions;
  final String rootPath;
  final String manifestPath;

  static SkillDocument loadFromDirectory(String directoryPath) {
    final root = Directory(directoryPath);
    final manifest = File(p.join(root.path, 'SKILL.md'));
    if (!root.existsSync() || !manifest.existsSync()) {
      throw const FormatException('Skill directory must contain SKILL.md.');
    }
    return parse(
      source: manifest.readAsStringSync(),
      rootPath: root.path,
      manifestPath: manifest.path,
    );
  }

  static SkillDocument parse({
    required String source,
    required String rootPath,
    required String manifestPath,
  }) {
    final normalized = source.replaceAll('\r\n', '\n');
    var metadata = const <String, Object?>{};
    var instructions = normalized.trim();
    if (normalized.startsWith('---\n')) {
      final end = normalized.indexOf('\n---\n', 4);
      if (end < 0) {
        throw const FormatException('Skill frontmatter is not closed.');
      }
      final yaml = loadYaml(normalized.substring(4, end));
      if (yaml is! YamlMap) {
        throw const FormatException('Skill frontmatter must be a YAML object.');
      }
      metadata = {
        for (final entry in yaml.entries) entry.key.toString(): entry.value,
      };
      instructions = normalized.substring(end + 5).trim();
    }
    if (instructions.isEmpty) {
      throw const FormatException('Skill instructions are empty.');
    }
    final fallbackName = p.basename(p.normalize(rootPath));
    final rawName = metadata['name'];
    final name = rawName is String && rawName.trim().isNotEmpty
        ? rawName.trim()
        : fallbackName;
    final rawDescription = metadata['description'];
    final description =
        rawDescription is String && rawDescription.trim().isNotEmpty
        ? rawDescription.trim()
        : _firstMeaningfulLine(instructions);
    return SkillDocument(
      name: name,
      description: description,
      instructions: instructions,
      rootPath: p.normalize(rootPath),
      manifestPath: manifestPath,
    );
  }

  String readRelativeResource(String relativePath) {
    final normalized = p.normalize(relativePath);
    if (p.isAbsolute(normalized) ||
        normalized == '..' ||
        normalized.startsWith('..${p.separator}')) {
      throw const FormatException('Skill resource escapes package root.');
    }
    final target = p.normalize(p.join(rootPath, normalized));
    if (!p.isWithin(rootPath, target) && target != rootPath) {
      throw const FormatException('Skill resource escapes package root.');
    }
    final file = File(target);
    if (!file.existsSync()) {
      throw const FormatException('Skill resource was not found.');
    }
    return file.readAsStringSync();
  }

  static String _firstMeaningfulLine(String value) {
    return value
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => 'Agent Skill');
  }
}
