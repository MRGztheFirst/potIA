import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../models/chat_attachment.dart';
import '../models/chat_message.dart';
import 'attachment_exception.dart';
import 'document_text.dart';

class AttachmentService {
  AttachmentService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  static const documentExtensions = ['pdf', 'docx', 'txt', 'md', 'csv'];
  static const imageExtensions = {'jpg', 'jpeg', 'png', 'webp'};
  static const maxImageBytes = 6 * 1024 * 1024;
  static const maxDocumentBytes = 15 * 1024 * 1024;
  static const double _maxImageSide = 1280;
  static const int _imageQuality = 82;

  final ImagePicker _picker;

  Future<ChatAttachment?> takePhoto(Directory into) async {
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: _maxImageSide,
      maxHeight: _maxImageSide,
      imageQuality: _imageQuality,
    );
    return file == null ? null : _importImage(file, into);
  }

  Future<List<ChatAttachment>> pickFromGallery(Directory into, {required int limit}) async {
    if (limit < 1) return [];
    final List<XFile> files;
    if (limit == 1) {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: _maxImageSide,
        maxHeight: _maxImageSide,
        imageQuality: _imageQuality,
      );
      files = file == null ? const [] : [file];
    } else {
      files = await _picker.pickMultiImage(
        maxWidth: _maxImageSide,
        maxHeight: _maxImageSide,
        imageQuality: _imageQuality,
        limit: limit,
      );
    }
    return [for (final file in files.take(limit)) await _importImage(file, into)];
  }

  Future<ChatAttachment?> pickDocument(Directory into) async {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: documentExtensions);
    if (file == null) return null;
    final extension = (file.extension ?? '').toLowerCase();
    if (!documentExtensions.contains(extension)) {
      throw const AttachmentException('Envie documentos em PDF, DOCX, TXT, MD ou CSV.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > maxDocumentBytes) throw const AttachmentException('O documento pode ter no máximo 15 MB.');

    final id = ChatMessage.newId();
    final target = File('${into.path}${Platform.pathSeparator}$id.$extension');
    await target.writeAsBytes(bytes, flush: true);
    try {
      final text = await DocumentText.extract(target, extension);
      return ChatAttachment(
        id: id,
        type: AttachmentType.document,
        name: file.name,
        path: target.path,
        sizeBytes: bytes.length,
        text: text,
      );
    } catch (_) {
      await discard([ChatAttachment(id: id, type: AttachmentType.document, name: file.name, path: target.path)]);
      rethrow;
    }
  }

  Future<void> discard(Iterable<ChatAttachment> attachments) async {
    for (final attachment in attachments) {
      try {
        final file = File(attachment.path);
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        continue;
      }
    }
  }

  Future<ChatAttachment> _importImage(XFile file, Directory into) async {
    final dot = file.name.lastIndexOf('.');
    var extension = dot == -1 ? 'jpg' : file.name.substring(dot + 1).toLowerCase();
    if (extension == 'jpeg') extension = 'jpg';
    if (!imageExtensions.contains(extension)) {
      throw const AttachmentException('Envie fotos em JPG, PNG ou WebP.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > maxImageBytes) throw const AttachmentException('Cada foto pode ter no máximo 6 MB.');

    final id = ChatMessage.newId();
    final target = File('${into.path}${Platform.pathSeparator}$id.$extension');
    await target.writeAsBytes(bytes, flush: true);
    return ChatAttachment(
      id: id,
      type: AttachmentType.image,
      name: file.name.replaceFirst(RegExp(r'^scaled_'), ''),
      path: target.path,
      sizeBytes: bytes.length,
    );
  }
}
