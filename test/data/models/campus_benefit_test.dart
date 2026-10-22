import 'package:biso/data/models/campus_benefit.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> item([Map<String, dynamic> overrides = const {}]) => {
  'id': 'b1',
  'campusId': 'oslo',
  'section': 'career',
  'category': 'Food',
  'title': {'nb': 'Tittel', 'en': 'Title'},
  'description': {'nb': 'Beskrivelse', 'en': null},
  'terms': {'nb': null, 'en': '  '},
  'imageUrl': 'https://img/x.png',
  'isFeatured': true,
  'partner': {
    'id': 'p1',
    'name': 'Partner AS',
    'logoUrl': null,
    'websiteUrl': 'https://p.no',
  },
  'publishEnd': '2026-12-31T23:00:00.000Z',
  'redemptionType': 'code',
  'sortOrder': 3,
  'createdAt': '2026-01-01T00:00:00.000Z',
  ...overrides,
};

void main() {
  test('parses a full item', () {
    final b = CampusBenefit.tryParse(item())!;
    expect(b.id, 'b1');
    expect(b.campusId, 'oslo');
    expect(b.section, BenefitSection.career);
    expect(b.category, 'Food');
    expect(b.title.nb, 'Tittel');
    expect(b.title.en, 'Title');
    expect(b.description.nb, 'Beskrivelse');
    expect(b.description.en, isNull);
    expect(b.terms.nb, isNull);
    expect(b.terms.en, isNull);
    expect(b.imageUrl, 'https://img/x.png');
    expect(b.isFeatured, isTrue);
    expect(b.partner?.name, 'Partner AS');
    expect(b.partner?.logoUrl, isNull);
    expect(b.partner?.websiteUrl, 'https://p.no');
    expect(b.publishEnd, DateTime.utc(2026, 12, 31, 23));
    expect(b.redemptionType, BenefitRedemptionType.code);
  });

  test('unknown enums fall back to member and none', () {
    final b = CampusBenefit.tryParse(
      item({'section': 'weird', 'redemptionType': 'teleport'}),
    )!;
    expect(b.section, BenefitSection.member);
    expect(b.redemptionType, BenefitRedemptionType.none);
  });

  test('nulls and missing optionals are tolerated', () {
    final b = CampusBenefit.tryParse(
      item({
        'partner': null,
        'publishEnd': null,
        'imageUrl': null,
        'category': null,
        'isFeatured': null,
      }),
    )!;
    expect(b.partner, isNull);
    expect(b.publishEnd, isNull);
    expect(b.imageUrl, isNull);
    expect(b.category, isNull);
    expect(b.isFeatured, isFalse);
  });

  test('title falls back between languages', () {
    final b = CampusBenefit.tryParse(
      item({
        'title': {'nb': ' ', 'en': 'Only en'},
      }),
    )!;
    expect(b.title.nb, isNull);
    expect(b.title.resolve('nb'), 'Only en');
    expect(b.title.resolve('en'), 'Only en');
  });

  test('malformed items return null', () {
    expect(CampusBenefit.tryParse(item({'id': null})), isNull);
    expect(CampusBenefit.tryParse(item({'campusId': 3})), isNull);
    expect(
      CampusBenefit.tryParse(
        item({
          'title': {'nb': '', 'en': null},
        }),
      ),
      isNull,
    );
    expect(CampusBenefit.tryParse(item({'title': 'x'})), isNull);
    expect(CampusBenefit.tryParse('nope'), isNull);
  });

  test('an unparseable publishEnd is treated as no end', () {
    expect(
      CampusBenefit.tryParse(item({'publishEnd': 'soon'}))!.publishEnd,
      isNull,
    );
  });

  test('a code or value in the payload is never kept', () {
    final b = CampusBenefit.tryParse(
      item({'code': 'SECRET', 'value': 'SECRET', 'redemptionValue': 'SECRET'}),
    )!;
    expect(b.toString(), isNot(contains('SECRET')));
    expect(b.props.map((e) => '$e').join(), isNot(contains('SECRET')));
  });
}
