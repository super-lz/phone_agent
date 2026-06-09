import 'package:flutter_gemma/core/di/service_registry.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/models/model_provider_config.dart';

class GemmaLocalModelException implements Exception {
  const GemmaLocalModelException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GemmaLocalRuntime {
  const GemmaLocalRuntime();

  Future<bool> isInstalled(ModelProviderConfig provider) {
    return FlutterGemma.isModelInstalled(provider.model);
  }

  Future<InferenceModel> getInferenceModel({
    required ModelProviderConfig provider,
    int? maxTokens,
    PreferredBackend preferredBackend = PreferredBackend.gpu,
  }) async {
    await ensureActiveModel(provider);
    try {
      return await FlutterGemma.getActiveModel(
        maxTokens: maxTokens ?? _maxTokensFor(provider),
        preferredBackend: preferredBackend,
      );
    } on Object catch (error) {
      throw GemmaLocalModelException(_activationErrorMessage(error));
    }
  }

  Future<void> ensureActiveModel(ModelProviderConfig provider) async {
    final installed = await FlutterGemma.isModelInstalled(provider.model);
    if (!installed) {
      throw const GemmaLocalModelException('本地模型未下载，请先到模型设置中下载或导入。');
    }

    try {
      await FlutterGemma.initialize();
    } catch (error) {
      AppLogger.warning('gemma.initialize_ignored', {
        'error': error.toString(),
      });
    }

    final manager = FlutterGemmaPlugin.instance.modelManager;
    final activeModel = manager.activeInferenceModel;
    final expectedFileType = _fileTypeFor(provider.model);
    if (_activeSpecMatches(
      activeModel,
      modelName: provider.model,
      fileType: expectedFileType,
    )) {
      return;
    }

    final modelInfo = await ServiceRegistry.instance.modelRepository.loadModel(
      provider.model,
    );
    if (modelInfo == null) {
      throw GemmaLocalModelException(
        '本地模型文件存在，但激活记录缺失。请在模型设置中重新导入 ${provider.model}。',
      );
    }

    final spec = InferenceModelSpec(
      name: _baseName(provider.model),
      modelSource: modelInfo.source,
      modelType: ModelType.gemma4,
      fileType: expectedFileType,
    );
    manager.setActiveModel(spec);
    AppLogger.info('gemma.active_model.restored', {
      'model': provider.model,
      'source': modelInfo.source.runtimeType.toString(),
    });
  }

  bool _activeSpecMatches(
    ModelSpec? spec, {
    required String modelName,
    required ModelFileType fileType,
  }) {
    if (spec is! InferenceModelSpec) {
      return false;
    }
    return spec.modelType == ModelType.gemma4 &&
        spec.fileType == fileType &&
        spec.files.any((file) => file.filename == modelName);
  }

  ModelFileType _fileTypeFor(String modelName) {
    final lower = modelName.toLowerCase();
    if (lower.endsWith('.litertlm')) {
      return ModelFileType.litertlm;
    }
    if (lower.endsWith('.task')) {
      return ModelFileType.task;
    }
    return ModelFileType.binary;
  }

  String _baseName(String modelName) {
    final slashIndex = modelName.lastIndexOf(RegExp(r'[/\\]'));
    final fileName = slashIndex >= 0
        ? modelName.substring(slashIndex + 1)
        : modelName;
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex <= 0) {
      return fileName;
    }
    return fileName.substring(0, dotIndex);
  }

  int _maxTokensFor(ModelProviderConfig provider) {
    final raw = provider.defaultParameters['max_tokens'];
    if (raw is int && raw > 0) {
      return raw;
    }
    return 4096;
  }

  String _activationErrorMessage(Object error) {
    final raw = error.toString();
    if (raw.contains('libStreamProxy.so') ||
        raw.contains('libLiteRtLm.so') ||
        raw.contains('Failed to load dynamic library')) {
      return '本地模型原生运行库缺失或未打包进当前 Android App。'
          '请重新构建并安装 App；如果构建时网络下载失败，需要先补齐 flutter_gemma 的 Android LiteRT-LM native assets。'
          '原始错误：$raw';
    }
    return '本地模型激活失败：$raw';
  }
}
