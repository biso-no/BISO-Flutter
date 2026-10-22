import 'dart:convert';

import 'package:biso/core/utils/rich_content.dart';
import 'package:flutter_test/flutter_test.dart';

String plate(List<Map<String, Object?>> blocks) => jsonEncode(blocks);

Map<String, Object?> p(List<Map<String, Object?>> children, [Map? extra]) => {
  'type': 'p',
  'children': children,
  ...?extra,
};

Map<String, Object?> leaf(String text, [Map? marks]) => {
  'text': text,
  ...?marks,
};

void main() {
  group('richContentToHtml', () {
    test('passes HTML through', () {
      expect(
        richContentToHtml('<p>Hei <strong>der</strong></p>'),
        '<p>Hei <strong>der</strong></p>',
      );
    });

    test('resolves entity-escaped markup so it renders, not shows tags', () {
      expect(
        richContentToHtml('&lt;p&gt;Rock &amp;amp; roll&lt;/p&gt;'),
        '<p>Rock &amp; roll</p>',
      );
    });

    test('turns plain text into paragraphs and keeps line breaks', () {
      expect(
        richContentToHtml('20 % rabatt\npå alt\r\n\r\nGjelder i butikk'),
        '<p>20 % rabatt<br>på alt</p><p>Gjelder i butikk</p>',
      );
    });

    test('escapes plain text, so a stray < is text', () {
      expect(
        richContentToHtml('Under <100 kr & mer'),
        '<p>Under &lt;100 kr &amp; mer</p>',
      );
    });

    test('a text that only looks like JSON stays text', () {
      expect(
        richContentToHtml('[Utsolgt] Hettegenser'),
        '<p>[Utsolgt] Hettegenser</p>',
      );
    });

    test('renders Plate blocks, marks and links', () {
      final value = plate([
        {
          'type': 'h2',
          'children': [leaf('Slik gjør du')],
        },
        p([
          leaf('Vis '),
          leaf('kortet', {'bold': true}),
          leaf(' i kassa', {'italic': true}),
          leaf(' – se '),
          {
            'type': 'a',
            'url': 'https://biso.no/?a=1&b="2"',
            'children': [leaf('vilkår')],
          },
        ]),
        {
          'type': 'hr',
          'children': [leaf('')],
        },
      ]);
      expect(
        richContentToHtml(value),
        '<h2>Slik gjør du</h2>'
        '<p>Vis <strong>kortet</strong><em> i kassa</em> – se '
        '<a href="https://biso.no/?a=1&amp;b=&quot;2&quot;">vilkår</a></p>'
        '<hr>',
      );
    });

    test('Plate text is escaped and keeps soft line breaks', () {
      expect(
        richContentToHtml(
          plate([
            p([leaf('<b>ikke fet</b>\nny linje')]),
          ]),
        ),
        '<p>&lt;b&gt;ikke fet&lt;/b&gt;<br>ny linje</p>',
      );
    });

    test('drops empty Plate paragraphs', () {
      expect(
        richContentToHtml(
          plate([
            p([leaf('Hei')]),
            p([leaf('')]),
          ]),
        ),
        '<p>Hei</p>',
      );
    });

    test('groups Plate list paragraphs into real lists', () {
      final value = plate([
        p([leaf('Du får:')]),
        p([leaf('Kaffe')], {'listStyleType': 'disc', 'indent': 1}),
        p([leaf('Med melk')], {'listStyleType': 'disc', 'indent': 2}),
        p([leaf('Kake')], {'listStyleType': 'disc', 'indent': 1}),
        p([leaf('Steg en')], {'listStyleType': 'decimal', 'indent': 1}),
        p([leaf('Ferdig')]),
      ]);
      expect(
        richContentToHtml(value),
        '<p>Du får:</p>'
        '<ul><li>Kaffe<ul><li>Med melk</li></ul></li><li>Kake</li></ul>'
        '<ol><li>Steg en</li></ol>'
        '<p>Ferdig</p>',
      );
    });

    test('renders the older ul/li/lic list shape', () {
      final value = plate([
        {
          'type': 'ul',
          'children': [
            {
              'type': 'li',
              'children': [
                {
                  'type': 'lic',
                  'children': [leaf('Én')],
                },
              ],
            },
          ],
        },
      ]);
      expect(richContentToHtml(value), '<ul><li>Én</li></ul>');
    });

    test('empty input is empty', () {
      expect(richContentToHtml('   '), '');
      expect(richContentToHtml('[]'), '');
    });
  });

  group('richContentToPlainText', () {
    test('strips tags and keeps block breaks', () {
      expect(
        richContentToPlainText(
          '<p>Én kaffe&nbsp;per uke.</p>\n<p>Gjelder <em>hverdager</em>.<br>Ikke helg.</p>',
        ),
        'Én kaffe per uke.\nGjelder hverdager.\nIkke helg.',
      );
    });

    test('collapses source whitespace inside HTML', () {
      expect(
        richContentToPlainText('<div>\n  Vis   kortet\n  i kassa\n</div>'),
        'Vis kortet i kassa',
      );
    });

    test('decodes numeric and named references', () {
      expect(
        richContentToPlainText(
          '<p>Kari&#39;s &#8211; &aring;pent &hellip;</p>',
        ),
        "Kari's – åpent …",
      );
    });

    test('flattens Plate JSON without splitting words at marks', () {
      final value = plate([
        p([
          leaf('Hel'),
          leaf('lo', {'bold': true}),
        ]),
        p([leaf('verden')], {'listStyleType': 'disc'}),
      ]);
      expect(richContentToPlainText(value), 'Hello\nverden');
    });

    test('keeps plain text as written', () {
      expect(
        richContentToPlainText('Linje én\nLinje to'),
        'Linje én\nLinje to',
      );
    });

    test('flattens entity-escaped markup', () {
      expect(richContentToPlainText('&lt;p&gt;Hei&lt;/p&gt;'), 'Hei');
    });
  });
}
