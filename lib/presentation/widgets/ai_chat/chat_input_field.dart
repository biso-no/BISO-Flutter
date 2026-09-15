import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../biso/biso.dart';

class ChatInputField extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final bool enabled;

  const ChatInputField({
    super.key,
    required this.controller,
    required this.onSend,
    this.enabled = true,
  });

  @override
  State<ChatInputField> createState() => _ChatInputFieldState();
}

class _ChatInputFieldState extends State<ChatInputField>
    with TickerProviderStateMixin {
  final FocusNode _focusNode = FocusNode();
  late AnimationController _scaleController;
  late AnimationController _rotationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;

  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _rotationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut),
    );

    _rotationAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _rotationController, curve: Curves.easeInOut),
    );

    widget.controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _scaleController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = widget.controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() {
        _hasText = hasText;
      });

      if (hasText) {
        _scaleController.forward();
        _rotationController.forward();
      } else {
        _scaleController.reverse();
        _rotationController.reverse();
      }
    }
  }

  void _onFocusChanged() {
    setState(() {});
  }

  void _handleSend() {
    if (widget.controller.text.trim().isNotEmpty && widget.enabled) {
      widget.onSend();
      _scaleController.reverse();
      _rotationController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);

    return Container(
      constraints: const BoxConstraints(minHeight: 52, maxHeight: 120),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildActionButton(
            palette: palette,
            icon: CupertinoIcons.paperclip,
            onPressed: _handleAttachment,
          ),
          const SizedBox(width: 8),
          Expanded(child: _buildTextField(context, palette)),
          const SizedBox(width: 8),
          _buildSendButton(palette),
        ],
      ),
    );
  }

  Widget _buildTextField(BuildContext context, BisoPalette palette) {
    return TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      decoration: bisoInputDecoration(
        context,
        hintText: 'Ask me anything about BISO...',
      ),
      style: Theme.of(
        context,
      ).textTheme.bodyLarge?.copyWith(color: palette.ink, height: 1.5),
      onSubmitted: (_) => _handleSend(),
    );
  }

  Widget _buildSendButton(BisoPalette palette) {
    final active = _hasText && widget.enabled;
    return AnimatedBuilder(
      animation: Listenable.merge([_scaleAnimation, _rotationAnimation]),
      builder: (context, child) {
        return ScaleTransition(
          scale: _scaleAnimation,
          child: RotationTransition(
            turns: _rotationAnimation,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: active ? palette.primary : palette.surfaceRaised,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: active ? _handleSend : null,
                  child: Icon(
                    CupertinoIcons.paperplane_fill,
                    color: active ? palette.onPrimary : palette.muted,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionButton({
    required BisoPalette palette,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onPressed,
          child: Icon(icon, color: palette.muted, size: 20),
        ),
      ),
    );
  }

  void _handleAttachment() {
    // TODO: Implement file attachment
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('File attachment coming soon!'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}
