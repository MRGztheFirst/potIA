import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/routes/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../widgets/potia_logo.dart';
import 'widgets/chat_input.dart';
import 'widgets/empty_chat.dart';
import 'widgets/message_bubble.dart';

class ChatView extends StatefulWidget {
  const ChatView({super.key});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _scrollController = ScrollController();
  late final AuthProvider _auth;
  late final ChatProvider _chat;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthProvider>();
    _chat = context.read<ChatProvider>();
    _auth.addListener(_onAuthChanged);
    _chat.addListener(_onChatChanged);
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    _chat.removeListener(_onChatChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onAuthChanged() {
    if (_leaving || !mounted || _auth.status != AuthStatus.unauthenticated) return;
    _leaving = true;
    _chat.clearConversation();
    Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.auth, (route) => false);
  }

  void _onChatChanged() {
    final nearBottom = !_scrollController.hasClients ||
        _scrollController.position.maxScrollExtent - _scrollController.position.pixels < 160;
    if (nearBottom) _scrollToBottom();
  }

  void _scrollToBottom({bool animated = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animated) {
        _scrollController.animateTo(target, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  void _send(String text) {
    _chat.sendMessage(text);
    _scrollToBottom(animated: true);
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sair da conta?'),
        content: const Text('Sua conversa atual será apagada deste aparelho.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sair')),
        ],
      ),
    );
    if (confirmed == true) await _auth.logout();
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final firstName = context.select<AuthProvider, String>((auth) => auth.user?.firstName ?? '');
    final messages = chat.messages;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 2,
        shadowColor: Colors.brown.withValues(alpha: 0.15),
        titleSpacing: 16,
        title: Row(
          children: [
            const PotiaLogo(size: 38),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PotIA', style: AppTheme.brandTitle(size: 22)),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    chat.isStreaming ? 'cozinhando...' : 'sua chef de bolso',
                    key: ValueKey(chat.isStreaming),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: chat.isStreaming ? AppColors.primary : AppColors.textMuted,
                        ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Nova conversa',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: chat.isEmpty ? null : chat.clearConversation,
          ),
          PopupMenuButton<String>(
            tooltip: 'Mais opções',
            onSelected: (value) {
              if (value == 'logout') _confirmLogout();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded, size: 20),
                    SizedBox(width: 12),
                    Text('Sair'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? EmptyChat(firstName: firstName, onSuggestion: _send)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final isLast = index == messages.length - 1;
                      return MessageBubble(
                        key: ValueKey(message.id),
                        message: message,
                        onRetry: isLast && message.hasError ? chat.retryLastAnswer : null,
                      );
                    },
                  ),
          ),
          ChatInput(isStreaming: chat.isStreaming, onSend: _send, onStop: chat.stopGeneration),
        ],
      ),
    );
  }
}
