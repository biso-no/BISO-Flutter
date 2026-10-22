import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/rich_content.dart';

/// Premium HTML renderer with BI brand styling.
///
/// Takes authored copy in any stored shape (HTML, Plate JSON or plain text);
/// see [richContentToHtml].
class PremiumHtmlRenderer extends StatelessWidget {
  final String htmlContent;
  final TextStyle? baseStyle;
  final EdgeInsets? padding;
  final int? maxLines;
  final TextOverflow overflow;
  final double? fontSize;
  final bool isCompact;

  const PremiumHtmlRenderer({
    super.key,
    required this.htmlContent,
    this.baseStyle,
    this.padding,
    this.maxLines,
    this.overflow = TextOverflow.visible,
    this.fontSize,
    this.isCompact = false,
  });

  /// Compact version for cards and previews
  const PremiumHtmlRenderer.compact({
    super.key,
    required this.htmlContent,
    this.baseStyle,
    this.padding,
    this.maxLines = 3,
    this.overflow = TextOverflow.ellipsis,
    this.fontSize = 14,
  }) : isCompact = true;

  /// Full version for detail screens
  const PremiumHtmlRenderer.full({
    super.key,
    required this.htmlContent,
    this.baseStyle,
    this.padding,
    this.maxLines,
    this.overflow = TextOverflow.visible,
    this.fontSize = 16,
  }) : isCompact = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultStyle = baseStyle ?? theme.textTheme.bodyMedium;
    final effectiveFontSize = fontSize ?? defaultStyle?.fontSize ?? 14;

    final html = richContentToHtml(htmlContent);
    if (html.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: padding,
      child: Html(
        data: html,
        style: _buildHtmlStyles(theme, effectiveFontSize),
        onLinkTap: _handleLinkTap,
      ),
    );
  }

  /// Build comprehensive HTML styles with theme-aware colors
  Map<String, Style> _buildHtmlStyles(ThemeData theme, double fontSize) {
    final colorScheme = theme.colorScheme;
    final onSurface = colorScheme.onSurface;
    final primary = colorScheme.primary;
    final surfaceHighest = colorScheme.surfaceContainerHighest;
    final outline = colorScheme.outline;

    return {
      // Base elements
      'body': Style(
        margin: Margins.zero,
        padding: HtmlPaddings.zero,
        fontSize: FontSize(fontSize),
        color: theme.textTheme.bodyMedium?.color ?? onSurface,
        fontFamily: theme.textTheme.bodyMedium?.fontFamily ?? 'Inter',
        lineHeight: LineHeight.percent(150),
        maxLines: maxLines,
      ),

      // Headings
      'h1': Style(
        fontSize: FontSize(isCompact ? fontSize + 6 : fontSize + 12),
        fontWeight: FontWeight.w700,
        color: onSurface,
        margin: Margins.only(bottom: 16, top: 8),
        lineHeight: LineHeight.percent(120),
      ),
      'h2': Style(
        fontSize: FontSize(isCompact ? fontSize + 4 : fontSize + 8),
        fontWeight: FontWeight.w600,
        color: primary,
        margin: Margins.only(bottom: 12, top: 6),
        lineHeight: LineHeight.percent(125),
      ),
      'h3': Style(
        fontSize: FontSize(isCompact ? fontSize + 2 : fontSize + 4),
        fontWeight: FontWeight.w600,
        color: primary,
        margin: Margins.only(bottom: 8, top: 4),
        lineHeight: LineHeight.percent(130),
      ),
      'h4': Style(
        fontSize: FontSize(fontSize + 2),
        fontWeight: FontWeight.w500,
        color: primary,
        margin: Margins.only(bottom: 6, top: 3),
      ),
      'h5': Style(
        fontSize: FontSize(fontSize + 1),
        fontWeight: FontWeight.w500,
        color: onSurface,
        margin: Margins.only(bottom: 4, top: 2),
      ),
      'h6': Style(
        fontSize: FontSize(fontSize),
        fontWeight: FontWeight.w500,
        color: primary,
        margin: Margins.only(bottom: 3, top: 1),
      ),

      // Paragraphs
      'p': Style(
        margin: Margins.only(bottom: isCompact ? 8 : 12),
        lineHeight: LineHeight.percent(150),
        textAlign: TextAlign.left,
      ),

      // Emphasis styling
      'strong': Style(fontWeight: FontWeight.w700, color: onSurface),
      'b': Style(fontWeight: FontWeight.w700, color: onSurface),
      'em': Style(fontStyle: FontStyle.italic, color: primary),
      'i': Style(fontStyle: FontStyle.italic, color: primary),

      // Links
      'a': Style(
        color: primary,
        textDecoration: TextDecoration.underline,
        fontWeight: FontWeight.w500,
      ),

      // Lists
      'ul': Style(
        margin: Margins.only(bottom: isCompact ? 8 : 12, left: 4),
        padding: HtmlPaddings.only(left: 16),
      ),
      'ol': Style(
        margin: Margins.only(bottom: isCompact ? 8 : 12, left: 4),
        padding: HtmlPaddings.only(left: 16),
      ),
      'li': Style(
        margin: Margins.only(bottom: 4),
        lineHeight: LineHeight.percent(140),
        display: Display.listItem,
      ),

      // Blockquotes
      'blockquote': Style(
        margin: Margins.only(left: 16, right: 16, bottom: 12),
        padding: HtmlPaddings.only(left: 16, top: 8, bottom: 8),
        border: Border(
          left: BorderSide(color: AppColors.defaultGold, width: 4),
        ),
        backgroundColor: primary.withValues(alpha: 0.08),
        fontStyle: FontStyle.italic,
        color: colorScheme.onSurfaceVariant,
      ),

      // Code styling
      'code': Style(
        backgroundColor: surfaceHighest,
        color: onSurface,
        padding: HtmlPaddings.symmetric(horizontal: 6, vertical: 2),
        fontSize: FontSize(fontSize - 1),
        fontFamily: 'monospace',
      ),
      'pre': Style(
        backgroundColor: surfaceHighest,
        padding: HtmlPaddings.all(12),
        margin: Margins.only(bottom: 12),
      ),

      // Tables
      'table': Style(
        border: Border.all(color: outline),
        width: Width(double.infinity),
        margin: Margins.only(bottom: 12),
      ),
      'th': Style(
        backgroundColor: primary.withValues(alpha: 0.12),
        padding: HtmlPaddings.all(8),
        fontWeight: FontWeight.w600,
        color: onSurface,
        border: Border.all(color: outline),
      ),
      'td': Style(
        padding: HtmlPaddings.all(8),
        border: Border.all(color: outline),
      ),

      // Compact mode overrides
      if (isCompact) ...{
        'h1': Style(
          fontSize: FontSize(fontSize + 6),
          fontWeight: FontWeight.w700,
          color: onSurface,
          margin: Margins.only(bottom: 4, top: 2),
        ),
        'h2': Style(
          fontSize: FontSize(fontSize + 4),
          fontWeight: FontWeight.w600,
          color: primary,
          margin: Margins.only(bottom: 4, top: 2),
        ),
        'h3': Style(
          fontSize: FontSize(fontSize + 2),
          fontWeight: FontWeight.w600,
          color: primary,
          margin: Margins.only(bottom: 4, top: 2),
        ),
        'p': Style(margin: Margins.only(bottom: 4)),
        'ul': Style(margin: Margins.only(bottom: 4)),
        'ol': Style(margin: Margins.only(bottom: 4)),
      },
    };
  }

  /// Handle link taps with URL launcher
  void _handleLinkTap(
    String? url,
    Map<String, String> attributes,
    dynamic element,
  ) {
    if (url != null && url.isNotEmpty) {
      _launchUrl(url);
    }
  }

  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      // Handle error - maybe show a snackbar
      debugPrint('Failed to launch URL: $url');
    }
  }
}

/// Extension for easy HTML rendering in existing widgets
extension StringHtmlExtension on String {
  Widget toPremiumHtml({
    TextStyle? style,
    EdgeInsets? padding,
    int? maxLines,
    TextOverflow overflow = TextOverflow.visible,
    double? fontSize,
    bool isCompact = false,
  }) {
    return PremiumHtmlRenderer(
      htmlContent: this,
      baseStyle: style,
      padding: padding,
      maxLines: maxLines,
      overflow: overflow,
      fontSize: fontSize,
      isCompact: isCompact,
    );
  }

  Widget toCompactHtml({
    TextStyle? style,
    EdgeInsets? padding,
    int? maxLines = 3,
    double? fontSize = 14,
  }) {
    return PremiumHtmlRenderer.compact(
      htmlContent: this,
      baseStyle: style,
      padding: padding,
      maxLines: maxLines,
      fontSize: fontSize,
    );
  }

  Widget toFullHtml({
    TextStyle? style,
    EdgeInsets? padding,
    double? fontSize = 16,
  }) {
    return PremiumHtmlRenderer.full(
      htmlContent: this,
      baseStyle: style,
      padding: padding,
      fontSize: fontSize,
    );
  }
}
