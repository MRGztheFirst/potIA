import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potia_app/models/chat_attachment.dart';
import 'package:potia_app/models/chat_message.dart';
import 'package:potia_app/providers/chat_provider.dart';
import 'package:potia_app/providers/history_provider.dart';
import 'package:potia_app/services/api_service.dart';
import 'package:potia_app/services/attachment_service.dart';
import 'package:potia_app/services/conversation_store.dart';
import 'package:potia_app/views/chat/widgets/message_bubble.dart';

class FakeApi extends ApiService {
  FakeApi() : super(baseUrl: 'http://teste');

  final requests = <List<Map<String, dynamic>>>[];

  @override
  Stream<String> streamChat(List<Map<String, dynamic>> messages) {
    requests.add(messages);
    return Stream.fromIterable(['Claro! ', 'Faça um molho.']);
  }
}

class FakeAttachments extends AttachmentService {
  FakeAttachments(this.photo);

  final ChatAttachment photo;

  @override
  Future<List<ChatAttachment>> pickFromGallery(Directory into, {required int limit}) async => [photo];
}

void main() {
  late Directory root;
  late FakeApi api;
  late ConversationStore store;
  late HistoryProvider history;
  late ChatProvider chat;
  late File photo;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('potia_chat');
    photo = File('${root.path}${Platform.pathSeparator}foto.jpg')..writeAsBytesSync([0xFF, 0xD8, 0xFF, 1, 2]);
    api = FakeApi();
    store = ConversationStore(root: () async => root);
    history = HistoryProvider(store: store);
    chat = ChatProvider(
      api: api,
      store: store,
      history: history,
      attachments: FakeAttachments(
        ChatAttachment(id: 'p1', type: AttachmentType.image, name: 'foto.jpg', path: photo.path),
      ),
    )..bindUser(3);
  });

  tearDown(() => root.delete(recursive: true));

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

  test('envia foto só na última mensagem e salva no histórico', () async {
    expect(await chat.addPhotosFromGallery(), isNull);
    expect(chat.pendingAttachments, hasLength(1));

    chat.sendMessage('Dá pra fazer molho?');
    await settle();
    expect(chat.pendingAttachments, isEmpty);
    expect(chat.messages.last.content, 'Claro! Faça um molho.');
    expect(api.requests.single.single['images'], [base64Encode([0xFF, 0xD8, 0xFF, 1, 2])]);

    chat.sendMessage('E com cebola?', fromVoice: true);
    await settle();
    final second = api.requests.last;
    expect(second.first.containsKey('images'), isFalse);
    expect(second.first['content'], contains('[1 foto(s) enviada(s) antes nesta conversa]'));
    expect(second.last, {'role': 'user', 'content': 'E com cebola?'});

    expect(history.items.single.title, 'Dá pra fazer molho?');
    final saved = await store.load(3, chat.conversationId!);
    expect(saved!.messages, hasLength(4));
    expect(saved.messages[2].fromVoice, isTrue);
    expect(saved.messages.first.images.single.path, photo.path);
  });

  test('abre conversa salva e começa uma nova', () async {
    chat.sendMessage('Receita de pão');
    await settle();
    final id = chat.conversationId!;

    chat.newConversation();
    expect(chat.messages, isEmpty);
    expect(chat.conversationId, isNull);

    expect(await chat.openConversation(id), isTrue);
    expect(chat.messages.map((m) => m.content), ['Receita de pão', 'Claro! Faça um molho.']);

    await chat.deleteConversation(id);
    expect(chat.messages, isEmpty);
    expect(history.items, isEmpty);
    expect(await store.load(3, id), isNull);
  });

  testWidgets('balões com foto, documento e voz renderizam', (tester) async {
    final messages = [
      ChatMessage.user('Olha isso', attachments: [
        ChatAttachment(id: 'p1', type: AttachmentType.image, name: 'foto.jpg', path: photo.path),
        const ChatAttachment(id: 'd1', type: AttachmentType.document, name: 'bolo.pdf', path: 'x', sizeBytes: 2048),
      ]),
      ChatMessage.user('Quero uma sopa', fromVoice: true),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: Column(children: [for (final m in messages) MessageBubble(message: m)])),
      ),
    ));
    expect(find.text('bolo.pdf'), findsOneWidget);
    expect(find.text('PDF · 2 KB'), findsOneWidget);
    expect(find.text('Mensagem de voz'), findsOneWidget);
    expect(find.text('Quero uma sopa'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
