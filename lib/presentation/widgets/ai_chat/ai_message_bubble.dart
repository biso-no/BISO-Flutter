import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../data/models/ai_chat_models.dart';
import '../../../core/constants/app_colors.dart';
import 'markdown_text.dart';

import '../../../core/logging/print_migration.dart';

class AiMessageBubble extends StatefulWidget {
  final ChatMessage message;
  final bool isStreaming;

  const AiMessageBubble({
    super.key,
    required this.message,
    this.isStreaming = false,
  });

  @override
  State<AiMessageBubble> createState() => _AiMessageBubbleState();
}

class _AiMessageBubbleState extends State<AiMessageBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(-0.1, 0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: const Interval(0.2, 1.0, curve: Curves.elasticOut),
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
    final isDark = theme.brightness == Brightness.dark;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAvatar(isDark),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tool results at the top in compact format
                  if (widget.message.toolParts.isNotEmpty) ...[
                    _buildCompactToolSummary(theme, isDark),
                    const SizedBox(height: 8),
                  ],
                  _buildMessageBubble(theme, isDark),
                  // Add sources section if we have SharePoint results
                  if (_hasSharePointSources()) ...[
                    const SizedBox(height: 12),
                    _buildSourcesSection(theme, isDark),
                  ],
                  const SizedBox(height: 4),
                  _buildTimestamp(theme),
                ],
              ),
            ),
            const SizedBox(width: 48), // Right margin for balance
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(bool isDark) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [AppColors.crystalBlue, AppColors.emeraldGreen],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.crystalBlue.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Icon(
        Icons.psychology_rounded,
        color: AppColors.white,
        size: 20,
      ),
    );
  }

  Widget _buildMessageBubble(ThemeData theme, bool isDark) {
    final textContent = widget.message.textContent;

    logPrint('🎨 [AI_BUBBLE] Building bubble for message ${widget.message.id}');
    logPrint(
      '📝 [AI_BUBBLE] Text content: "$textContent" (length: ${textContent.length})',
    );
    logPrint('⏳ [AI_BUBBLE] Is streaming: ${widget.isStreaming}');
    logPrint('🧩 [AI_BUBBLE] Message parts: ${widget.message.parts.length}');

    // Only hide bubble if there's no text content, no tool parts, and not streaming
    if (textContent.isEmpty &&
        widget.message.toolParts.isEmpty &&
        !widget.isStreaming) {
      logPrint(
        '👻 [AI_BUBBLE] Returning empty bubble - no content, no tools, and not streaming',
      );
      return const SizedBox.shrink();
    }

    // If no text but has tool parts, show a placeholder message
    final hasToolParts = widget.message.toolParts.isNotEmpty;
    logPrint(
      '🔧 [AI_BUBBLE] Has tool parts: $hasToolParts (${widget.message.toolParts.length})',
    );

    if (textContent.isEmpty && hasToolParts && !widget.isStreaming) {
      logPrint('🔧 [AI_BUBBLE] Showing tool-only response');
    }

    return GestureDetector(
      onLongPress: () => _copyToClipboard(textContent),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: (isDark ? AppColors.surfaceDark : AppColors.white)
                  .withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: (isDark ? AppColors.outlineDark : AppColors.outline)
                    .withValues(alpha: 0.2),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color:
                      (isDark ? AppColors.shadowHeavy : AppColors.shadowLight)
                          .withValues(alpha: 0.1),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (textContent.isNotEmpty)
                  MarkdownText(
                    text: textContent,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      height: 1.6,
                      color: isDark
                          ? AppColors.onSurfaceDark
                          : AppColors.onSurface,
                    ),
                  )
                else if (hasToolParts && !widget.isStreaming)
                  // Show placeholder when there are tools but no text response
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Found information using search tools:',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color:
                            (isDark
                                    ? AppColors.onSurfaceDark
                                    : AppColors.onSurface)
                                .withValues(alpha: 0.7),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                if (widget.isStreaming && textContent.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: 4),
                      _buildStreamingCursor(),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStreamingCursor() {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Opacity(
          opacity: (_animationController.value * 2) % 1.0 > 0.5 ? 1.0 : 0.3,
          child: Container(
            width: 2,
            height: 16,
            decoration: BoxDecoration(
              color: AppColors.crystalBlue,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompactToolSummary(ThemeData theme, bool isDark) {
    logPrint(
      '🔧 [AI_BUBBLE] Building compact tool summary for message ${widget.message.id}',
    );
    logPrint(
      '🔧 [AI_BUBBLE] Tool parts count: ${widget.message.toolParts.length}',
    );

    final completedTools = widget.message.toolParts
        .where((tool) => tool.state == ToolPartState.outputAvailable)
        .toList();

    final runningTools = widget.message.toolParts
        .where(
          (tool) =>
              tool.state == ToolPartState.inputStreaming ||
              tool.state == ToolPartState.inputAvailable,
        )
        .toList();

    if (completedTools.isEmpty && runningTools.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.crystalBlue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.crystalBlue.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 16,
                color: AppColors.crystalBlue,
              ),
              const SizedBox(width: 8),
              Text(
                'Used Tools',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.crystalBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              // Show completed tools
              ...completedTools.map(
                (tool) => _buildToolChip(theme, tool, true),
              ),
              // Show running tools
              ...runningTools.map((tool) => _buildToolChip(theme, tool, false)),
            ],
          ),
          // Show search summaries if available
          if (completedTools.any((t) => t.toolName == 'searchSharePoint'))
            _buildSearchSummary(
              theme,
              completedTools.firstWhere(
                (t) => t.toolName == 'searchSharePoint',
              ),
              'document',
            ),
          if (completedTools.any((t) => t.toolName == 'searchSiteContent'))
            _buildSearchSummary(
              theme,
              completedTools.firstWhere(
                (t) => t.toolName == 'searchSiteContent',
              ),
              'result',
            ),
        ],
      ),
    );
  }

  Widget _buildToolChip(ThemeData theme, ToolPart tool, bool isCompleted) {
    final color = isCompleted ? AppColors.emeraldGreen : AppColors.crystalBlue;
    final icon = isCompleted
        ? Icons.check_circle_rounded
        : Icons.hourglass_empty_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            _getToolDisplayName(tool.toolName),
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w500,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchSummary(ThemeData theme, ToolPart searchTool, String itemType) {
    final result = searchTool.result;
    if (result == null) return const SizedBox.shrink();

    try {
      final results = result['results'] as List<dynamic>? ?? [];
      final query = result['query'] as String? ?? '';
      if (results.isEmpty) return const SizedBox.shrink();

      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            Icon(Icons.search_rounded, size: 14, color: AppColors.emeraldGreen),
            const SizedBox(width: 6),
            Text(
              'Found ${results.length} $itemType${results.length == 1 ? '' : 's'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.emeraldGreen,
                fontWeight: FontWeight.w500,
                fontSize: 11,
              ),
            ),
            if (query.isNotEmpty) ...[
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  '• "$query"',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      );
    } catch (e) {
      return const SizedBox.shrink();
    }
  }

  String _getToolDisplayName(String toolName) {
    switch (toolName) {
      case 'searchSharePoint':
        return 'Document Search';
      case 'searchSiteContent':
        return 'Site Content';
      case 'getDocumentStats':
        return 'Document Stats';
      case 'listSharePointSites':
        return 'Sites';
      case 'weather':
        return 'Weather';
      default:
        return toolName;
    }
  }

  Widget _buildTimestamp(ThemeData theme) {
    if (widget.message.timestamp == null) {
      return const SizedBox.shrink();
    }

    final time = TimeOfDay.fromDateTime(widget.message.timestamp!);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppColors.onSurfaceVariant,
          fontSize: 11,
        ),
      ),
    );
  }

  void _copyToClipboard(String text) {
    if (text.isNotEmpty) {
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

  bool _hasSharePointSources() {
    final hasSources = widget.message.toolParts.any(
      (tool) =>
          (tool.toolName == 'searchSharePoint' ||
              tool.toolName == 'searchSiteContent') &&
          tool.state == ToolPartState.outputAvailable &&
          tool.result != null,
    );

    if (hasSources) {
      logPrint(
        '📚 [AI_BUBBLE] Has search sources for message ${widget.message.id}',
      );
    }

    return hasSources;
  }

  Widget _buildSourcesSection(ThemeData theme, bool isDark) {
    final searchTools = widget.message.toolParts
        .where(
          (tool) =>
              (tool.toolName == 'searchSharePoint' ||
                  tool.toolName == 'searchSiteContent') &&
              tool.state == ToolPartState.outputAvailable &&
              tool.result != null,
        )
        .toList();

    if (searchTools.isEmpty) return const SizedBox.shrink();

    final sources = <Map<String, String>>[];

    for (final tool in searchTools) {
      final result = tool.result;
      final results = result?['results'] as List<dynamic>? ?? [];

      logPrint(
        '📚 [AI_BUBBLE] Processing ${tool.toolName} with ${results.length} results',
      );

      for (final item in results) {
        final title = item['title'] as String?;
        // Handle both documentViewerUrl (SharePoint) and url (SiteContent)
        final url = item['documentViewerUrl'] as String? ?? item['url'] as String?;
        logPrint('📚 [AI_BUBBLE] Source item: title="$title", url="$url"');
        if (title != null && url != null) {
          sources.add({'title': title, 'url': url});
        }
      }
    }

    logPrint('📚 [AI_BUBBLE] Total sources found: ${sources.length}');

    if (sources.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (isDark ? AppColors.stoneGray : AppColors.surfaceVariant)
            .withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (isDark ? AppColors.outlineDark : AppColors.outline)
              .withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.link_rounded, size: 16, color: AppColors.crystalBlue),
              const SizedBox(width: 8),
              Text(
                '${sources.length} Source${sources.length == 1 ? '' : 's'}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.crystalBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: sources
                .take(5)
                .map((source) => _buildSourceChip(theme, source))
                .toList(),
          ),
          if (sources.length > 5) ...[
            const SizedBox(height: 8),
            Text(
              '+ ${sources.length - 5} more documents',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSourceChip(ThemeData theme, Map<String, String> source) {
    return GestureDetector(
      onTap: () => _launchUrl(source['url']!),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.crystalBlue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.crystalBlue.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.open_in_new_rounded,
              size: 12,
              color: AppColors.crystalBlue,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                source['title']!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.crystalBlue,
                  fontWeight: FontWeight.w500,
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Failed to launch URL: $url, Error: $e');
    }
  }
}
