import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../../domain/conversation/message_block.dart';

class WorkbenchAttachmentPicker {
  const WorkbenchAttachmentPicker();

  Future<List<MessageBlock>> pickSystemFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: true,
      withData: false,
    );
    if (result == null || result.files.isEmpty) {
      return const [];
    }
    return [
      for (final file in result.files)
        MessageBlock.fileAttachment(
          name: file.name,
          uri: _uriForPickedFile(file),
          bytes: file.size,
          extension: file.extension,
        ),
    ];
  }

  Future<List<MessageBlock>> pickGalleryImages() async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage(
      maxWidth: 2000,
      maxHeight: 2000,
      imageQuality: 85,
    );
    if (images.isEmpty) {
      return const [];
    }
    final blocks = <MessageBlock>[];
    for (final image in images) {
      blocks.add(await _blockForPickedImage(image));
    }
    return blocks;
  }

  Future<List<MessageBlock>> takePhoto() async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 2000,
      maxHeight: 2000,
      imageQuality: 85,
    );
    if (photo == null) {
      return const [];
    }
    return [await _blockForPickedImage(photo)];
  }

  Future<MessageBlock> _blockForPickedImage(XFile image) async {
    return MessageBlock.image(
      name: image.name,
      uri: Uri.file(image.path).toString(),
      bytes: await image.length(),
      mimeType: _imageMimeType(image.path.split('.').last),
    );
  }

  String _uriForPickedFile(PlatformFile file) {
    final path = file.path;
    if (path != null && path.isNotEmpty) {
      return Uri.file(path).toString();
    }
    return file.identifier ?? file.name;
  }

  String? _imageMimeType(String? extension) {
    switch (extension?.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      default:
        return null;
    }
  }
}
