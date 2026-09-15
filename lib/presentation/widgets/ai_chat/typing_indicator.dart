import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../biso/biso.dart';

class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  late final AnimationController _animationController;
  late final List<Animation<double>> _dotAnimations;
  bool _animating = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    // Create staggered animations for each dot
    _dotAnimations = List.generate(3, (index) {
      return Tween<double>(begin: 0.4, end: 1.0).animate(
        CurvedAnimation(
          parent: _animationController,
          curve: Interval(
            index * 0.2,
            0.6 + (index * 0.2),
            curve: Curves.easeInOut,
          ),
        ),
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A repeating controller never settles, so `pumpAndSettle` would hang
    // forever in tests (and reduced-motion users don't want the loop
    // running); leave the dots at their static starting opacity instead.
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    if (disableAnimations) {
      if (_animating) {
        _animationController.stop();
        _animating = false;
      }
    } else if (!_animating) {
      _animationController.repeat();
      _animating = true;
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BisoIconTile(
          icon: CupertinoIcons.sparkles,
          accent: BisoAccent.violet,
          size: 28,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...List.generate(3, (index) {
                  return AnimatedBuilder(
                    animation: _dotAnimations[index],
                    builder: (context, child) {
                      return Container(
                        margin: EdgeInsets.only(left: index > 0 ? 4 : 0),
                        child: Opacity(
                          opacity: _dotAnimations[index].value,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: palette.muted,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'AI is thinking...',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(
                      color: palette.muted,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 48), // Right margin for balance
      ],
    );
  }
}
