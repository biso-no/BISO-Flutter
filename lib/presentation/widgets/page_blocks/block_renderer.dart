import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../premium/premium_html_renderer.dart';

/// Maps a serialized page-editor block to a native Flutter widget.
/// Unsupported block types return [SizedBox.shrink] so the screen
/// degrades gracefully as new block types are added on the web.
class BlockRenderer extends StatelessWidget {
  final Map<String, dynamic> block;

  const BlockRenderer({super.key, required this.block});

  static Widget forBlock(Map<String, dynamic> block) =>
      BlockRenderer(key: ValueKey(block['id']), block: block);

  @override
  Widget build(BuildContext context) {
    final type = block['type'] as String? ?? '';
    switch (type) {
      case 'hero':
        return _HeroBlock(block: block);
      case 'text':
        return _TextBlock(block: block);
      case 'stats':
        return _StatsBlock(block: block);
      case 'callout':
        return _CalloutBlock(block: block);
      case 'cta':
        return _CtaBlock(block: block);
      case 'image':
        return _ImageBlock(block: block);
      case 'gallery':
        return _GalleryBlock(block: block);
      // events / jobs / news have dedicated native screens — skip silently
      default:
        return const SizedBox.shrink();
    }
  }
}

// ─── Hero ────────────────────────────────────────────────────────────────────

class _HeroBlock extends StatelessWidget {
  final Map<String, dynamic> block;
  const _HeroBlock({required this.block});

  @override
  Widget build(BuildContext context) {
    final heading = block['heading'] as String? ?? '';
    final subtitle = block['subtitle'] as String? ?? '';
    final accent = _parseColor(block['accentColor'] as String?);
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: accent, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (heading.isNotEmpty)
            Text(
              heading,
              style: theme.textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(subtitle, style: theme.textTheme.bodyLarge),
          ],
        ],
      ),
    );
  }
}

// ─── Text ─────────────────────────────────────────────────────────────────────

class _TextBlock extends StatelessWidget {
  final Map<String, dynamic> block;
  const _TextBlock({required this.block});

  @override
  Widget build(BuildContext context) {
    final items = (block['body'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();

    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items.map((item) {
          final text = item['text'] as String? ?? '';
          if (text.isEmpty) return const SizedBox.shrink();
          // text may contain inline HTML (<b>, <i>, <a>) from the format bar
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: PremiumHtmlRenderer.full(htmlContent: text),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Stats ────────────────────────────────────────────────────────────────────

class _StatsBlock extends StatelessWidget {
  final Map<String, dynamic> block;
  const _StatsBlock({required this.block});

  @override
  Widget build(BuildContext context) {
    final items = (block['items'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    if (items.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: items.map((item) {
          final value = item['value'] as String? ?? '';
          final label = item['label'] as String? ?? '';
          return Expanded(
            child: Column(
              children: [
                Text(
                  value,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  label,
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Callout ──────────────────────────────────────────────────────────────────

class _CalloutBlock extends StatelessWidget {
  final Map<String, dynamic> block;
  const _CalloutBlock({required this.block});

  @override
  Widget build(BuildContext context) {
    final text = block['text'] as String? ?? '';
    final accent = _parseColor(block['accentColor'] as String?);
    if (text.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: PremiumHtmlRenderer.full(htmlContent: text),
    );
  }
}

// ─── CTA ──────────────────────────────────────────────────────────────────────

class _CtaBlock extends StatelessWidget {
  final Map<String, dynamic> block;
  const _CtaBlock({required this.block});

  @override
  Widget build(BuildContext context) {
    final label = block['label'] as String? ?? '';
    final url = block['url'] as String? ?? '';
    if (label.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: FilledButton(
        onPressed: url.isNotEmpty
            ? () => launchUrl(Uri.parse(url),
                mode: LaunchMode.externalApplication)
            : null,
        child: Text(label),
      ),
    );
  }
}

// ─── Image ────────────────────────────────────────────────────────────────────

class _ImageBlock extends StatelessWidget {
  final Map<String, dynamic> block;
  const _ImageBlock({required this.block});

  @override
  Widget build(BuildContext context) {
    final src = block['src'] as String? ?? '';
    final caption = block['caption'] as String? ?? '';
    if (src.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Image.network(
            src,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
          if (caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Text(
                caption,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Gallery ──────────────────────────────────────────────────────────────────

class _GalleryBlock extends StatelessWidget {
  final Map<String, dynamic> block;
  const _GalleryBlock({required this.block});

  @override
  Widget build(BuildContext context) {
    final images = (block['images'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    if (images.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 160,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: images.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final src = images[i]['src'] as String? ?? '';
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: src.isNotEmpty
                ? Image.network(
                    src,
                    width: 140,
                    height: 144,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox(width: 140),
                  )
                : const SizedBox(width: 140),
          );
        },
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

Color _parseColor(String? hex) {
  if (hex == null || hex.isEmpty) return Colors.blue;
  try {
    final clean = hex.replaceFirst('#', '');
    return Color(int.parse('FF$clean', radix: 16));
  } catch (_) {
    return Colors.blue;
  }
}
