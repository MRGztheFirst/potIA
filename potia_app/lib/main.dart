import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/history_provider.dart';
import 'services/api_service.dart';
import 'services/attachment_service.dart';
import 'services/conversation_store.dart';
import 'services/speech_service.dart';
import 'services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storage = await StorageService.create();
  final api = ApiService();
  final store = ConversationStore();
  final history = HistoryProvider(store: store);

  runApp(
    MultiProvider(
      providers: [
        Provider<ApiService>.value(value: api),
        Provider<SpeechService>(create: (_) => SpeechService()),
        ChangeNotifierProvider(create: (_) => AuthProvider(api: api, storage: storage)),
        ChangeNotifierProvider.value(value: history),
        ChangeNotifierProvider(
          create: (_) => ChatProvider(api: api, store: store, history: history, attachments: AttachmentService()),
        ),
      ],
      child: const PotiaApp(),
    ),
  );
}
