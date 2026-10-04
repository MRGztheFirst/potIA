import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/conversation.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/chat_provider.dart';
import '../../../providers/history_provider.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/potia_logo.dart';

class HistoryDrawer extends StatelessWidget {
  const HistoryDrawer({super.key, required this.onLogout});

  final VoidCallback onLogout;

  static String sectionFor(DateTime date, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'Hoje';
    if (diff == 1) return 'Ontem';
    if (diff < 7) return 'Últimos 7 dias';
    if (diff < 30) return 'Últimos 30 dias';
    return 'Mais antigas';
  }

  @override
  Widget build(BuildContext context) {
    final history = context.watch<HistoryProvider>();
    final currentId = context.select<ChatProvider, String?>((chat) => chat.conversationId);
    final user = context.select<AuthProvider, String>((auth) => auth.user?.name ?? '');
    final now = DateTime.now();

    final children = <Widget>[];
    String? lastSection;
    for (final item in history.items) {
      final section = sectionFor(item.updatedAt, now);
      if (section != lastSection) {
        children.add(_SectionHeader(section));
        lastSection = section;
      }
      children.add(_ConversationTile(item: item, selected: item.id == currentId));
    }

    return Drawer(
      backgroundColor: AppColors.cream,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
              child: Row(
                children: [
                  const PotiaLogo(size: 34),
                  const SizedBox(width: 10),
                  Text('Conversas', style: AppTheme.brandTitle(size: 22)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () {
                  context.read<ChatProvider>().newConversation();
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('Nova conversa'),
              ),
            ),
            Expanded(
              child: history.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : history.items.isEmpty
                      ? const _EmptyHistory()
                      : ListView(padding: const EdgeInsets.only(bottom: 12), children: children),
            ),
            const Divider(height: 1),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.creamDeep,
                child: Text(
                  user.isEmpty ? '?' : user.characters.first.toUpperCase(),
                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800),
                ),
              ),
              title: Text(user, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                tooltip: 'Sair',
                icon: const Icon(Icons.logout_rounded),
                onPressed: () {
                  Navigator.of(context).pop();
                  onLogout();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w800,
              ),
        ),
      );
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 48, color: AppColors.primary.withValues(alpha: 0.4)),
              const SizedBox(height: 12),
              Text(
                'Suas conversas com a PotIA aparecem aqui.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      );
}

enum _TileAction { rename, delete }

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.item, required this.selected});

  final ConversationSummary item;
  final bool selected;

  Future<void> _open(BuildContext context) async {
    final scaffold = Scaffold.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final opened = await context.read<ChatProvider>().openConversation(item.id);
    scaffold.closeDrawer();
    if (!opened) {
      messenger.showSnackBar(const SnackBar(content: Text('Não foi possível abrir esta conversa.')));
    }
  }

  Future<void> _rename(BuildContext context) async {
    final chat = context.read<ChatProvider>();
    final title = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(initial: item.title),
    );
    if (title != null) await chat.renameConversation(item.id, title);
  }

  Future<void> _delete(BuildContext context) async {
    final chat = context.read<ChatProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apagar conversa?'),
        content: Text('"${item.title}" e os anexos dela serão apagados deste aparelho.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await chat.deleteConversation(item.id);
    if (context.mounted) showAppSnackBar(context, 'Conversa apagada.');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: ListTile(
        selected: selected,
        selectedTileColor: AppColors.creamDeep,
        selectedColor: AppColors.textDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding: const EdgeInsets.only(left: 14, right: 2),
        title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: item.preview.isEmpty
            ? null
            : Text(item.preview, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
        onTap: () => _open(context),
        onLongPress: () => _rename(context),
        trailing: PopupMenuButton<_TileAction>(
          tooltip: 'Opções da conversa',
          icon: const Icon(Icons.more_vert_rounded, color: AppColors.textMuted),
          onSelected: (action) => switch (action) {
            _TileAction.rename => _rename(context),
            _TileAction.delete => _delete(context),
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: _TileAction.rename,
              child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Renomear'), dense: true),
            ),
            PopupMenuItem(
              value: _TileAction.delete,
              child: ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: AppColors.error),
                title: Text('Apagar', style: TextStyle(color: AppColors.error)),
                dense: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final title = _controller.text.trim();
    if (title.isNotEmpty) Navigator.pop(context, title);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Renomear conversa'),
        content: TextField(
          controller: _controller,
          autofocus: true,
          maxLength: 60,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (_) => _save(),
          decoration: const InputDecoration(hintText: 'Nome da conversa'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          TextButton(onPressed: _save, child: const Text('Salvar')),
        ],
      );
}
