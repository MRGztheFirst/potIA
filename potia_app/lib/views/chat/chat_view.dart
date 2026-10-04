import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/routes/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/potia_logo.dart';
import 'widgets/attachment_sheet.dart';
import 'widgets/chat_input.dart';
import 'widgets/empty_chat.dart';
import 'widgets/history_drawer.dart';
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
  bool _followBottom = true;
  String? _shownConversation;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthProvider>();
    _chat = context.read<ChatProvider>();
    _auth.addListener(_onAuthChanged);
    _chat.addListener(_onChatChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bindUser());
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    _chat.removeListener(_onChatChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _bindUser() {
    final user = _auth.user;
    if (user == null || !mounted) return;
    _chat.bindUser(user.id);
  }

  void _onAuthChanged() {
    if (_leaving || !mounted || _auth.status != AuthStatus.unauthenticated) return;
    _leaving = true;
    _chat.reset();
    Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.auth, (route) => false);
  }

  void _onChatChanged() {
    if (_chat.conversationId != _shownConversation) {
      _shownConversation = _chat.conversationId;
      _followBottom = true;
    }
    if (_followBottom) _scrollToBottom();
  }

  bool _onScroll(ScrollNotification notification) {
    final byUser = notification is UserScrollNotification ||
        (notification is ScrollUpdateNotification && notification.dragDetails != null);
    if (byUser) _followBottom = notification.metrics.maxScrollExtent - notification.metrics.pixels < 80;
    return false;
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

  void _send(String text, {bool fromVoice = false}) {
    _followBottom = true;
    _chat.sendMessage(text, fromVoice: fromVoice);
    _scrollToBottom(animated: true);
  }

  Future<void> _attach() async {
    final source = await showAttachmentSheet(
      context,
      canAddImage: _chat.remainingImageSlots > 0,
      canAddDocument: _chat.canAddDocument,
    );
    if (source == null) return;
    final error = await switch (source) {
      AttachmentSource.camera => _chat.addPhotoFromCamera(),
      AttachmentSource.gallery => _chat.addPhotosFromGallery(),
      AttachmentSource.document => _chat.addDocument(),
    };
    if (error != null && mounted) showAppSnackBar(context, error, isError: true);
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sair da conta?'),
        content: const Text('Suas conversas continuam salvas neste aparelho para quando você voltar.'),
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
      drawer: HistoryDrawer(onLogout: _confirmLogout),
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 2,
        shadowColor: Colors.brown.withValues(alpha: 0.15),
        titleSpacing: 0,
        leading: Builder(
          builder: (context) => IconButton(
            tooltip: 'Conversas',
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Row(
          children: [
            const PotiaLogo(size: 36),
            const SizedBox(width: 10),
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
            onPressed: chat.isEmpty ? null : chat.newConversation,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? EmptyChat(firstName: firstName, onSuggestion: _send)
                : NotificationListener<ScrollNotification>(
                    onNotification: _onScroll,
                    child: ListView.builder(
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
          ),
          ChatInput(
            isStreaming: chat.isStreaming,
            isAttaching: chat.isAttaching,
            pending: chat.pendingAttachments,
            onSend: _send,
            onVoiceSend: (text) => _send(text, fromVoice: true),
            onStop: chat.stopGeneration,
            onAttach: _attach,
            onRemoveAttachment: (attachment) => chat.removePendingAttachment(attachment.id),
          ),
        ],
      ),
    );
  }
}
