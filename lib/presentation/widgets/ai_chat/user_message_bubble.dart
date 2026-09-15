import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/models/ai_chat_models.dart';
import '../biso/biso.dart';

class UserMessageBubble extends StatefulWidget {
  final ChatMessage message;

  const UserMessageBubble({super.key, required this.message});

  @override
  State<UserMessageBubble> createState() => _UserMessageBubbleState();
}

class _UserMessageBubbleState extends State<UserMessageBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.elasticOut),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = BisoPalette.of(context);

    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(width: 48), // Left margin for balance
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _buildMessageBubble(theme, palette),
                  const SizedBox(height: 4),
                  _buildTimestamp(theme, palette),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _buildAvatar(palette),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(BisoPalette palette) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: palette.primary,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Icon(
        CupertinoIcons.person_fill,
        color: palette.onPrimary,
        size: 20,
      ),
    );
  }

  Widget _buildMessageBubble(ThemeData theme, BisoPalette palette) {
    final textContent = widget.message.textContent;

    if (textContent.isEmpty) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: () => _showInteractionFeedback(),
      onLongPress: () => _copyToClipboard(textContent),
      child: Container(
        key: ValueKey('ai-user-bubble-${widget.message.id}'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: palette.primary,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          textContent,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: palette.onPrimary,
            height: 1.6,
          ),
        ),
      ),
    );
  }

  Widget _buildTimestamp(ThemeData theme, BisoPalette palette) {
    if (widget.message.timestamp == null) {
      return const SizedBox.shrink();
    }

    final time = TimeOfDay.fromDateTime(widget.message.timestamp!);
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Text(
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: palette.muted,
          fontSize: 11,
        ),
      ),
    );
  }

  void _showInteractionFeedback() {
    // Add a subtle scale animation on tap
    _animationController.reverse().then((_) {
      _animationController.forward();
    });
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Message copied to clipboard'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
