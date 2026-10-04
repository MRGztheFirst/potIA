import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potia_app/core/utils/validators.dart';
import 'package:potia_app/models/chat_attachment.dart';
import 'package:potia_app/models/chat_message.dart';
import 'package:potia_app/models/conversation.dart';
import 'package:potia_app/services/attachment_exception.dart';
import 'package:potia_app/services/conversation_store.dart';
import 'package:potia_app/services/document_text.dart';
import 'package:potia_app/services/sse_parser.dart';
import 'package:potia_app/views/chat/widgets/history_drawer.dart';

void main() {
  group('Validators', () {
    test('email', () {
      expect(Validators.email('ana@potia.com'), isNull);
      expect(Validators.email('ana-potia.com'), 'E-mail inválido');
      expect(Validators.email(''), 'Informe seu e-mail');
    });

    test('senha de cadastro', () {
      expect(Validators.newPassword('receita123'), isNull);
      expect(Validators.newPassword('curta1'), 'A senha deve ter pelo menos 8 caracteres');
      expect(Validators.newPassword('semnumeros'), 'Inclua pelo menos um número');
      expect(Validators.newPassword('12345678'), 'Inclua pelo menos uma letra');
    });

    test('confirmação de senha', () {
      final validator = Validators.confirmPassword(() => 'receita123');
      expect(validator('receita123'), isNull);
      expect(validator('outra123'), 'As senhas não coincidem');
    });
  });

  group('SseParser', () {
    test('agrupa linhas data em eventos', () async {
      final lines = Stream.fromIterable([
        ': keep-alive',
        'data: {"type":"token","content":"Olá"}',
        '',
        'event: fim',
        'data: linha 1',
        'data: linha 2',
        '',
      ]);
      final events = await lines.transform(const SseParser()).toList();
      expect(events, hasLength(2));
      expect(events[0].data, '{"type":"token","content":"Olá"}');
      expect(events[1].event, 'fim');
      expect(events[1].data, 'linha 1\nlinha 2');
    });
  });

  group('ChatMessage', () {
    test('converte para o formato da API', () {
      final message = ChatMessage.user('Como fazer pão?');
      expect(message.toApiJson(), {'role': 'user', 'content': 'Como fazer pão?'});
      expect(ChatMessage.assistantPlaceholder().isStreaming, isTrue);
    });

    test('inclui documentos e fotos no conteúdo da API', () {
      final message = ChatMessage.user('Adapte esta receita', attachments: const [
        ChatAttachment(id: 'd1', type: AttachmentType.document, name: 'bolo.txt', path: 'x', text: '3 ovos'),
        ChatAttachment(id: 'i1', type: AttachmentType.image, name: 'foto.jpg', path: 'y'),
      ]);
      expect(message.toApiJson(encodedImages: ['QUJD']), {
        'role': 'user',
        'content': 'Adapte esta receita\n\n[Documento anexado: bolo.txt]\n3 ovos',
        'images': ['QUJD'],
      });
      expect(
        message.toApiJson()['content'],
        endsWith('[1 foto(s) enviada(s) antes nesta conversa]'),
      );
    });

    test('documento longo é cortado', () {
      final message = ChatMessage.user('', attachments: [
        ChatAttachment(id: 'd1', type: AttachmentType.document, name: 'a.txt', path: 'x', text: 'a' * 9000),
      ]);
      final content = message.apiContent;
      expect(content, contains('[...documento cortado]'));
      expect(content.length, lessThan(8200));
    });

    test('salva e restaura em JSON', () {
      final original = ChatMessage.user('Oi', fromVoice: true, attachments: const [
        ChatAttachment(id: 'i1', type: AttachmentType.image, name: 'foto.jpg', path: '/tmp/foto.jpg', sizeBytes: 2048),
      ]);
      final restored = ChatMessage.fromJson(original.toJson());
      expect(restored.content, 'Oi');
      expect(restored.fromVoice, isTrue);
      expect(restored.images.single.path, '/tmp/foto.jpg');
      expect(restored.images.single.readableSize, '2 KB');

      final streaming = ChatMessage.assistantPlaceholder().copyWith(content: 'Meia resposta');
      expect(ChatMessage.fromJson(streaming.toJson()).status, MessageStatus.done);
    });
  });

  group('Conversation', () {
    test('gera título a partir da primeira mensagem', () {
      expect(Conversation.titleFor(ChatMessage.user('  Como   fazer pão?  ')), 'Como fazer pão?');
      expect(Conversation.titleFor(ChatMessage.user('a' * 60)), '${'a' * 42}…');
      expect(
        Conversation.titleFor(ChatMessage.user('', attachments: const [
          ChatAttachment(id: 'i1', type: AttachmentType.image, name: 'f.jpg', path: 'x'),
        ])),
        'Foto',
      );
    });

    test('agrupa o histórico por data', () {
      final now = DateTime(2026, 10, 4, 15);
      expect(HistoryDrawer.sectionFor(DateTime(2026, 10, 4, 1), now), 'Hoje');
      expect(HistoryDrawer.sectionFor(DateTime(2026, 10, 3, 23), now), 'Ontem');
      expect(HistoryDrawer.sectionFor(DateTime(2026, 9, 30), now), 'Últimos 7 dias');
      expect(HistoryDrawer.sectionFor(DateTime(2026, 9, 10), now), 'Últimos 30 dias');
      expect(HistoryDrawer.sectionFor(DateTime(2025, 1, 1), now), 'Mais antigas');
    });
  });

  group('ConversationStore', () {
    late Directory root;
    late ConversationStore store;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('potia_test');
      store = ConversationStore(root: () async => root);
    });

    tearDown(() => root.delete(recursive: true));

    Conversation conversation(String id, String title, DateTime updatedAt, {List<ChatAttachment> attachments = const []}) =>
        Conversation(
          id: id,
          title: title,
          createdAt: updatedAt,
          updatedAt: updatedAt,
          messages: [ChatMessage.user('Pergunta $id', attachments: attachments)],
        );

    test('salva, lista, renomeia e apaga com os anexos', () async {
      final dir = await store.attachmentsDir(7);
      final photo = File('${dir.path}${Platform.pathSeparator}foto.jpg')..writeAsBytesSync([1, 2, 3]);
      final attachment = ChatAttachment(id: 'i1', type: AttachmentType.image, name: 'foto.jpg', path: photo.path);

      await store.save(7, conversation('a', 'Bolo', DateTime(2026, 1, 1)));
      await store.save(7, conversation('b', 'Pão', DateTime(2026, 2, 1), attachments: [attachment]));
      expect((await store.list(7)).map((c) => c.id), ['b', 'a']);
      expect(await store.list(8), isEmpty);

      await store.rename(7, 'a', 'Bolo de cenoura');
      expect((await store.load(7, 'a'))!.title, 'Bolo de cenoura');
      expect((await store.list(7)).last.title, 'Bolo de cenoura');

      await store.delete(7, 'b');
      expect((await store.list(7)).map((c) => c.id), ['a']);
      expect(await store.load(7, 'b'), isNull);
      expect(photo.existsSync(), isFalse);
    });
  });

  group('DocumentText', () {
    test('extrai texto de DOCX', () {
      const xml = '<w:document><w:body>'
          '<w:p><w:r><w:t>Bolo de fubá</w:t></w:r></w:p>'
          '<w:p><w:r><w:t>3 ovos &amp; 1 xícara</w:t></w:r></w:p>'
          '</w:body></w:document>';
      final archive = Archive()..add(ArchiveFile.string('word/document.xml', xml));
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
      expect(DocumentText.normalize(DocumentText.fromDocx(bytes)), 'Bolo de fubá\n3 ovos & 1 xícara');
    });

    test('lê texto em latin1 quando não é UTF-8', () {
      final bytes = Uint8List.fromList(latin1.encode('Pão de queijo'));
      expect(DocumentText.decodePlainText(bytes), 'Pão de queijo');
    });

    test('DOCX inválido gera erro amigável', () {
      expect(
        () => DocumentText.fromDocx(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<AttachmentException>()),
      );
    });
  });
}
