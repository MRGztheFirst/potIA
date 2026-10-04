import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/chat_attachment.dart';
import '../../../services/speech_service.dart';
import '../../widgets/app_snackbar.dart';
import 'attachment_views.dart';

class ChatInput extends StatefulWidget {
  const ChatInput({
    super.key,
    required this.isStreaming,
    required this.onSend,
    required this.onStop,
    this.onVoiceSend,
    this.onAttach,
    this.pending = const [],
    this.isAttaching = false,
    this.onRemoveAttachment,
  });

  final bool isStreaming;
  final ValueChanged<String> onSend;
  final VoidCallback onStop;
  final ValueChanged<String>? onVoiceSend;
  final VoidCallback? onAttach;
  final List<ChatAttachment> pending;
  final bool isAttaching;
  final ValueChanged<ChatAttachment>? onRemoveAttachment;

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;

  SpeechService? _speech;
  bool _listening = false;
  String _voiceText = '';
  double _level = 0;
  Timer? _finalResultTimer;

  bool get _canSend => (_hasText || widget.pending.isNotEmpty) && !widget.isAttaching;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) setState(() => _hasText = hasText);
    });
  }

  @override
  void dispose() {
    _finalResultTimer?.cancel();
    if (_listening) _speech?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_canSend || widget.isStreaming) return;
    widget.onSend(_controller.text.trim());
    _controller.clear();
    _focusNode.requestFocus();
  }

  Future<void> _startVoice() async {
    final speech = _speech ??= context.read<SpeechService>();
    FocusScope.of(context).unfocus();
    setState(() {
      _listening = true;
      _voiceText = '';
      _level = 0;
    });
    final started = await speech.start(
      onResult: (words, isFinal) {
        if (!mounted || !_listening) return;
        setState(() => _voiceText = words);
        if (isFinal) _finishVoice(send: true);
      },
      onStatus: (status) {
        if (status == 'done') _finishVoice(send: true);
      },
      onError: (error) {
        if (!mounted || !_listening) return;
        _finishVoice(send: false);
        showAppSnackBar(context, _voiceErrorMessage(error), isError: true);
      },
      onLevel: (level) {
        if (mounted && _listening) setState(() => _level = level);
      },
    );
    if (!started && mounted) {
      setState(() => _listening = false);
      showAppSnackBar(
        context,
        'O reconhecimento de voz não está disponível. Confira a permissão do microfone.',
        isError: true,
      );
    }
  }

  Future<void> _stopAndSend() async {
    await _speech?.stop();
    _finalResultTimer?.cancel();
    _finalResultTimer = Timer(const Duration(milliseconds: 1200), () => _finishVoice(send: true));
  }

  Future<void> _cancelVoice() async {
    _finishVoice(send: false);
    await _speech?.cancel();
  }

  void _finishVoice({required bool send}) {
    if (!_listening || !mounted) return;
    _finalResultTimer?.cancel();
    final text = _voiceText.trim();
    setState(() {
      _listening = false;
      _voiceText = '';
    });
    if (!send) return;
    if (text.isEmpty) {
      showAppSnackBar(context, 'Não ouvi nada. Tente falar de novo.', isError: true);
    } else {
      widget.onVoiceSend?.call(text);
    }
  }

  static String _voiceErrorMessage(String error) => switch (error) {
        'error_no_match' || 'error_speech_timeout' => 'Não ouvi nada. Tente falar de novo.',
        'error_permission' || 'error_insufficient_permissions' => 'Permita o uso do microfone para enviar áudio.',
        'error_network' || 'error_network_timeout' || 'error_server' => 'Sem conexão para reconhecer a voz.',
        'error_busy' => 'O microfone está ocupado. Tente de novo.',
        _ => 'Não consegui entender o áudio.',
      };

  @override
  Widget build(BuildContext context) {
    final showPending = widget.pending.isNotEmpty || widget.isAttaching;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cream,
        boxShadow: [
          BoxShadow(color: Colors.brown.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showPending && !_listening)
              PendingAttachments(
                attachments: widget.pending,
                isLoading: widget.isAttaching,
                onRemove: (attachment) => widget.onRemoveAttachment?.call(attachment),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _listening ? _buildVoiceBar() : _buildTextRow(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextRow() {
    final Widget action;
    if (widget.isStreaming) {
      action = _RoundButton(
        key: const ValueKey('stop'),
        icon: Icons.stop_rounded,
        tooltip: 'Parar resposta',
        onPressed: widget.onStop,
      );
    } else if (_canSend || widget.onVoiceSend == null) {
      action = _RoundButton(
        key: const ValueKey('send'),
        icon: Icons.send_rounded,
        tooltip: 'Enviar',
        onPressed: _canSend ? _submit : null,
      );
    } else {
      action = _RoundButton(
        key: const ValueKey('mic'),
        icon: Icons.mic_rounded,
        tooltip: 'Enviar áudio',
        onPressed: widget.isAttaching ? null : _startVoice,
      );
    }

    return Row(
      key: const ValueKey('text-row'),
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (widget.onAttach != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: IconButton(
              tooltip: 'Anexar foto ou documento',
              onPressed: widget.isStreaming || widget.isAttaching ? null : widget.onAttach,
              icon: const Icon(Icons.add_circle_outline_rounded, size: 30),
              color: AppColors.primary,
            ),
          )
        else
          const SizedBox(width: 4),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: AppColors.creamDeep),
            ),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                hintText: 'Pergunte à PotIA...',
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
          child: action,
        ),
      ],
    );
  }

  Widget _buildVoiceBar() {
    final pulse = 1 + (_level.clamp(0, 10) / 25);
    return Row(
      key: const ValueKey('voice-bar'),
      children: [
        IconButton(
          tooltip: 'Cancelar áudio',
          onPressed: _cancelVoice,
          icon: const Icon(Icons.delete_outline_rounded, size: 28),
          color: AppColors.textMuted,
        ),
        Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                AnimatedScale(
                  scale: pulse,
                  duration: const Duration(milliseconds: 120),
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _voiceText.isEmpty ? 'Ouvindo... pode falar' : _voiceText,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _voiceText.isEmpty ? AppColors.textMuted : AppColors.textDark,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        _RoundButton(
          key: const ValueKey('voice-send'),
          icon: Icons.check_rounded,
          tooltip: 'Enviar áudio',
          onPressed: _stopAndSend,
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({super.key, required this.icon, required this.tooltip, this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        shape: const CircleBorder(),
        color: enabled ? AppColors.primary : AppColors.primary.withValues(alpha: 0.35),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(width: 50, height: 50, child: Icon(icon, color: Colors.white)),
        ),
      ),
    );
  }
}
