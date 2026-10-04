import 'package:flutter/foundation.dart';

import '../models/conversation.dart';
import '../services/conversation_store.dart';

class HistoryProvider extends ChangeNotifier {
  HistoryProvider({required ConversationStore store}) : _store = store;

  final ConversationStore _store;
  List<ConversationSummary> _items = [];
  int? _userId;
  bool _isLoading = false;

  List<ConversationSummary> get items => List.unmodifiable(_items);
  bool get isLoading => _isLoading;

  Future<void> loadFor(int userId) async {
    if (_userId == userId) return;
    _userId = userId;
    _items = [];
    _isLoading = true;
    notifyListeners();
    try {
      final loaded = await _store.list(userId);
      if (_userId != userId) return;
      final recent = {for (final item in _items) item.id};
      _items = [..._items, ...loaded.where((item) => !recent.contains(item.id))];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void upsert(ConversationSummary summary) {
    _items = [summary, for (final item in _items) if (item.id != summary.id) item];
    notifyListeners();
  }

  Future<void> rename(String id, String title) async {
    final userId = _userId;
    final clean = title.trim();
    if (userId == null || clean.isEmpty) return;
    _items = [for (final item in _items) item.id == id ? item.copyWith(title: clean) : item];
    notifyListeners();
    await _store.rename(userId, id, clean);
  }

  Future<void> delete(String id) async {
    final userId = _userId;
    if (userId == null) return;
    _items = _items.where((item) => item.id != id).toList();
    notifyListeners();
    await _store.delete(userId, id);
  }

  void clear() {
    _userId = null;
    _items = [];
    notifyListeners();
  }
}
