import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'services/api_service.dart';
import 'services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storage = await StorageService.create();
  final api = ApiService();

  runApp(
    MultiProvider(
      providers: [
        Provider<ApiService>.value(value: api),
        ChangeNotifierProvider(create: (_) => AuthProvider(api: api, storage: storage)),
        ChangeNotifierProvider(create: (_) => ChatProvider(api: api)),
      ],
      child: const PotiaApp(),
    ),
  );
}
