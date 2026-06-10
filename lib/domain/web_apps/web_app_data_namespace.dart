import '../artifacts/artifact.dart';

class WebAppDataNamespace {
  const WebAppDataNamespace._();

  static String database({
    required String workspaceId,
    required AgentArtifact webApp,
  }) {
    final declared = webApp.metadata['databaseNamespace'];
    if (declared is String && declared.trim().isNotEmpty) {
      return declared.trim();
    }
    return databaseForId(workspaceId: workspaceId, webAppId: webApp.id);
  }

  static String files({
    required String workspaceId,
    required AgentArtifact webApp,
  }) {
    final declared = webApp.metadata['fileNamespace'];
    if (declared is String && declared.trim().isNotEmpty) {
      return declared.trim();
    }
    return filesForId(workspaceId: workspaceId, webAppId: webApp.id);
  }

  static String databaseForId({
    required String workspaceId,
    required String webAppId,
  }) {
    return '$workspaceId::webapp::${_safeSegment(webAppId)}::db';
  }

  static String filesForId({
    required String workspaceId,
    required String webAppId,
  }) {
    return '$workspaceId::webapp::${_safeSegment(webAppId)}::files';
  }

  static String forCapability({
    required String capabilityId,
    required String workspaceId,
    required AgentArtifact webApp,
  }) {
    if (capabilityId == 'db.note.create' || capabilityId == 'db.note.query') {
      return database(workspaceId: workspaceId, webApp: webApp);
    }
    if (capabilityId == 'file.read_app_file' ||
        capabilityId == 'file.write_app_file' ||
        capabilityId == 'file.search_app_files') {
      return files(workspaceId: workspaceId, webApp: webApp);
    }
    return workspaceId;
  }

  static String _safeSegment(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  }
}
