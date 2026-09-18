import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:phone_agent/application/skills/skill_document.dart';

void main() {
  test('parses standard frontmatter and keeps instructions separate', () {
    final document = SkillDocument.parse(
      source: '''---
name: release-check
description: Validate a release before publishing.
---
# Release check

Read the changelog, then run the supported checks.
''',
      rootPath: '/tmp/release-check',
      manifestPath: '/tmp/release-check/SKILL.md',
    );

    expect(document.name, 'release-check');
    expect(document.description, 'Validate a release before publishing.');
    expect(document.instructions, contains('Read the changelog'));
  });

  test('relative resources cannot escape the skill package', () {
    final root = Directory.systemTemp.createTempSync('phone-agent-skill-');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/SKILL.md').writeAsStringSync('# Instructions\nUse it.');
    File('${root.path}/notes.md').writeAsStringSync('Package note');
    final document = SkillDocument.loadFromDirectory(root.path);

    expect(document.readRelativeResource('notes.md'), 'Package note');
    expect(
      () => document.readRelativeResource('../outside.md'),
      throwsFormatException,
    );
  });

  test('rejects unterminated frontmatter and empty instructions', () {
    expect(
      () => SkillDocument.parse(
        source: '---\nname: incomplete',
        rootPath: '/tmp/incomplete',
        manifestPath: '/tmp/incomplete/SKILL.md',
      ),
      throwsFormatException,
    );
    expect(
      () => SkillDocument.parse(
        source: '---\nname: empty\n---\n',
        rootPath: '/tmp/empty',
        manifestPath: '/tmp/empty/SKILL.md',
      ),
      throwsFormatException,
    );
  });
}
