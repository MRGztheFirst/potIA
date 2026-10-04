import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdfrx/pdfrx.dart';

import 'attachment_exception.dart';

class DocumentText {
  DocumentText._();

  static const plainTextExtensions = {'txt', 'md', 'csv'};

  static Future<String> extract(File file, String extension) async {
    final bytes = await file.readAsBytes();
    final text = switch (extension) {
      'pdf' => await _fromPdf(file),
      'docx' => fromDocx(bytes),
      _ when plainTextExtensions.contains(extension) => decodePlainText(bytes),
      _ => throw const AttachmentException('Formato de documento não suportado.'),
    };
    return normalize(text);
  }

  static String decodePlainText(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }

  static String fromDocx(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const AttachmentException('Não consegui abrir o arquivo DOCX.');
    }
    final document = archive.findFile('word/document.xml');
    if (document == null) throw const AttachmentException('O arquivo DOCX está vazio ou corrompido.');
    final xml = utf8.decode(document.content, allowMalformed: true);
    final text = xml
        .replaceAll(RegExp(r'</w:p>'), '\n')
        .replaceAll(RegExp(r'<w:(tab|br|cr)\s*/>'), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), '');
    return _unescapeXml(text);
  }

  static String normalize(String text) => text
      .replaceAll('\r\n', '\n')
      .replaceAll(RegExp(r'[ \t ]+'), ' ')
      .replaceAll(RegExp(r' *\n *'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  static Future<String> _fromPdf(File file) async {
    PdfDocument? document;
    try {
      await pdfrxFlutterInitialize();
      document = await PdfDocument.openFile(file.path);
      final pages = <String>[];
      for (final page in document.pages) {
        final text = await page.loadText();
        if (text != null && text.fullText.trim().isNotEmpty) pages.add(text.fullText);
      }
      return pages.join('\n\n');
    } on AttachmentException {
      rethrow;
    } catch (_) {
      throw const AttachmentException('Não consegui ler o PDF. Ele pode estar protegido por senha.');
    } finally {
      await document?.dispose();
    }
  }

  static String _unescapeXml(String text) => text
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}
