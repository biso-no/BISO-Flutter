/// Readers for authored copy: descriptions, bodies, terms.
///
/// A row holds its copy in one of three shapes, depending on where it came
/// from: HTML (legacy and imported content), Plate JSON (the block editor)
/// or plain text (the studio's text fields). The web reads all three
/// (`packages/ui/components/plate-content-renderer.tsx` and
/// `apps/web/src/lib/content-text.ts` in BISO-Sites), so the app must too:
/// handing any of them straight to a `Text` shows tags or raw JSON.
library;

import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// [value] as HTML, whatever shape it is stored in.
String richContentToHtml(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  final blocks = _plateBlocks(trimmed);
  if (blocks != null) return _plateToHtml(blocks);
  // Some imported rows hold entity-escaped markup (`&lt;p&gt;`). Unescape it
  // once so it renders instead of showing its tags.
  final source = _escapedTag.hasMatch(trimmed)
      ? _decodeEntities(trimmed)
      : trimmed;
  if (_htmlTag.hasMatch(source)) return source;
  return _textToHtml(_decodeEntities(trimmed));
}

/// [value] as plain text, whatever shape it is stored in: no tags, entities
/// resolved, one line per paragraph, line break or list item.
String richContentToPlainText(String value) {
  final html = richContentToHtml(value);
  if (html.isEmpty) return '';
  final out = StringBuffer();
  _writeText(html_parser.parseFragment(html), out);
  return out
      .toString()
      .split('\n')
      .map((line) => line.replaceAll(_spaces, ' ').trim())
      .where((line) => line.isNotEmpty)
      .join('\n');
}

final _htmlTag = RegExp(r'<!--|</?[a-zA-Z][a-zA-Z0-9-]*(?:\s[^<>]*)?/?>');
final _escapedTag = RegExp(r'&lt;/?[a-zA-Z]');
final _spaces = RegExp(r'[ \t ]+');
final _whitespace = RegExp(r'\s+');
final _blankLine = RegExp(r'\n\s*\n');
final _entity = RegExp(r'&(#[xX][0-9a-fA-F]+|#[0-9]+|[a-zA-Z][a-zA-Z0-9]*);');

const _escapeText = HtmlEscape(HtmlEscapeMode.element);
const _escapeAttribute = HtmlEscape(HtmlEscapeMode.attribute);

/// Plain text: blank lines part paragraphs, single newlines are line breaks.
String _textToHtml(String text) => text
    .replaceAll('\r\n', '\n')
    .split(_blankLine)
    .map((paragraph) => paragraph.trim())
    .where((paragraph) => paragraph.isNotEmpty)
    .map((paragraph) {
      final escaped = _escapeText.convert(paragraph).replaceAll('\n', '<br>');
      return '<p>$escaped</p>';
    })
    .join();

// ── Plate JSON ──────────────────────────────────────────────────────────────

/// The blocks when [value] is a Plate document, else null. Text that only
/// starts with "[" ("[Utsolgt] Hettegenser") is not one.
List<Map<Object?, Object?>>? _plateBlocks(String value) {
  if (!value.startsWith('[')) return null;
  try {
    final decoded = jsonDecode(value);
    if (decoded is List && decoded.every((node) => node is Map)) {
      return decoded.cast<Map<Object?, Object?>>();
    }
  } on FormatException {
    // Not JSON: it is text.
  }
  return null;
}

/// List styles the list plugin numbers; any other style is a bullet.
const _orderedListStyles = {
  'decimal',
  'decimal-leading-zero',
  'lower-alpha',
  'upper-alpha',
  'lower-latin',
  'upper-latin',
  'lower-roman',
  'upper-roman',
};

/// The block editor's list plugin keeps a list as a run of paragraphs, each
/// with a `listStyleType` and an `indent` (its depth). They are gathered here
/// into nested `<ul>`/`<ol>` elements; the web's serializer drops them.
String _plateToHtml(List<Map<Object?, Object?>> blocks) {
  final out = StringBuffer();
  final open = <({String tag, int indent})>[];
  void close() => out.write('</li></${open.removeLast().tag}>');

  for (final block in blocks) {
    final style = block['listStyleType'];
    if (style is! String || style.isEmpty) {
      while (open.isNotEmpty) {
        close();
      }
      out.write(_plateNode(block));
      continue;
    }
    final indent = block['indent'] is num
        ? (block['indent']! as num).toInt()
        : 1;
    final tag = _orderedListStyles.contains(style) ? 'ol' : 'ul';
    while (open.isNotEmpty &&
        (open.last.indent > indent ||
            (open.last.indent == indent && open.last.tag != tag))) {
      close();
    }
    final item = _plateChildren(block);
    if (open.isNotEmpty && open.last.indent == indent) {
      out.write('</li><li>$item');
    } else {
      out.write('<$tag><li>$item');
      open.add((tag: tag, indent: indent));
    }
  }
  while (open.isNotEmpty) {
    close();
  }
  return out.toString();
}

String _plateChildren(Map<Object?, Object?> node) {
  final children = node['children'];
  if (children is! List) return '';
  return children.map(_plateNode).join();
}

String _plateNode(Object? node) {
  if (node is! Map) return '';
  final text = node['text'];
  if (text is String) return _plateLeaf(node, text);

  final children = _plateChildren(node);
  final type = node['type'];
  switch (type) {
    case 'p' || 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6' || 'blockquote':
      // The editor leaves empty paragraphs behind; they would only add gaps.
      return children.trim().isEmpty ? '' : '<$type>$children</$type>';
    case 'ul' || 'ol' || 'li' || 'table' || 'tr' || 'td' || 'th':
      return '<$type>$children</$type>';
    case 'lic':
      return children;
    case 'hr':
      return '<hr>';
    case 'a':
      final url = node['url'];
      if (url is! String || url.isEmpty) return children;
      return '<a href="${_escapeAttribute.convert(url)}">$children</a>';
    case 'img':
      final url = node['url'];
      if (url is! String || url.isEmpty) return '';
      return '<img src="${_escapeAttribute.convert(url)}">';
    case 'code_block':
      return '<pre><code>$children</code></pre>';
    case 'code_line':
      return '$children\n';
    case 'callout':
      return '<blockquote>$children</blockquote>';
    default:
      return '<div>$children</div>';
  }
}

String _plateLeaf(Map<Object?, Object?> leaf, String text) {
  var html = _escapeText.convert(text).replaceAll('\n', '<br>');
  if (leaf['bold'] == true) html = '<strong>$html</strong>';
  if (leaf['italic'] == true) html = '<em>$html</em>';
  if (leaf['underline'] == true) html = '<u>$html</u>';
  if (leaf['strikethrough'] == true) html = '<s>$html</s>';
  if (leaf['code'] == true) html = '<code>$html</code>';
  return html;
}

// ── Plain text ──────────────────────────────────────────────────────────────

/// Elements that sit inside a line. Every other element starts a new one.
const _inlineTags = {
  'a',
  'abbr',
  'b',
  'cite',
  'code',
  'del',
  'em',
  'i',
  'ins',
  'kbd',
  'mark',
  'q',
  's',
  'small',
  'span',
  'strike',
  'strong',
  'sub',
  'sup',
  'u',
};

void _writeText(dom.Node node, StringBuffer out) {
  if (node is dom.Text) {
    // HTML source whitespace (a newline in the markup) is just a space.
    out.write(node.data.replaceAll(_whitespace, ' '));
    return;
  }
  if (node is dom.Element) {
    final tag = node.localName;
    if (tag == 'script' || tag == 'style') return;
    if (tag == 'br') {
      out.write('\n');
      return;
    }
    if (!_inlineTags.contains(tag)) {
      out.write('\n');
      for (final child in node.nodes) {
        _writeText(child, out);
      }
      out.write('\n');
      return;
    }
  }
  for (final child in node.nodes) {
    _writeText(child, out);
  }
}

// ── Character references ────────────────────────────────────────────────────

const _namedEntities = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'ndash': '–',
  'mdash': '—',
  'lsquo': '‘',
  'rsquo': '’',
  'ldquo': '“',
  'rdquo': '”',
  'laquo': '«',
  'raquo': '»',
  'hellip': '…',
  'bull': '•',
  'middot': '·',
  'copy': '©',
  'reg': '®',
  'trade': '™',
  'euro': '€',
  'aelig': 'æ',
  'AElig': 'Æ',
  'oslash': 'ø',
  'Oslash': 'Ø',
  'aring': 'å',
  'Aring': 'Å',
  'auml': 'ä',
  'Auml': 'Ä',
  'ouml': 'ö',
  'Ouml': 'Ö',
  'uuml': 'ü',
  'Uuml': 'Ü',
  'eacute': 'é',
  'Eacute': 'É',
};

/// Resolves numeric references and the named ones Norwegian copy uses; an
/// unknown reference is left as written. One pass, so `&amp;lt;` is `&lt;`.
String _decodeEntities(String value) => value.replaceAllMapped(_entity, (m) {
  final ref = m[1]!;
  if (!ref.startsWith('#')) return _namedEntities[ref] ?? m[0]!;
  final hex = ref.startsWith('#x') || ref.startsWith('#X');
  final code = int.tryParse(ref.substring(hex ? 2 : 1), radix: hex ? 16 : 10);
  final valid =
      code != null &&
      code > 0 &&
      code <= 0x10FFFF &&
      (code < 0xD800 || code > 0xDFFF);
  return valid ? String.fromCharCode(code) : m[0]!;
});
