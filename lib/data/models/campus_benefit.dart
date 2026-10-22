import 'package:equatable/equatable.dart';

/// Which part of the benefits page a benefit belongs to.
enum BenefitSection { member, career, social, safety, business }

/// How a member claims a benefit.
enum BenefitRedemptionType { code, link, onsite, none }

/// A string in both site languages. Either side may be missing.
class BenefitText extends Equatable {
  const BenefitText({this.nb, this.en});

  factory BenefitText.fromJson(Object? json) {
    final map = json is Map ? json : const <String, Object?>{};
    return BenefitText(nb: _text(map['nb']), en: _text(map['en']));
  }

  final String? nb;
  final String? en;

  /// The text for [languageCode] (`nb`/`no` or `en`), falling back to the
  /// other language; null when neither exists.
  String? resolve(String languageCode) {
    final isEnglish = languageCode == 'en';
    return isEnglish ? (en ?? nb) : (nb ?? en);
  }

  @override
  List<Object?> get props => [nb, en];
}

/// The partner behind a benefit.
class BenefitPartner extends Equatable {
  const BenefitPartner({
    required this.id,
    required this.name,
    this.logoUrl,
    this.websiteUrl,
  });

  static BenefitPartner? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = _text(json['id']);
    final name = _text(json['name']);
    if (id == null || name == null) return null;
    return BenefitPartner(
      id: id,
      name: name,
      logoUrl: _text(json['logoUrl']),
      websiteUrl: _text(json['websiteUrl']),
    );
  }

  final String id;
  final String name;
  final String? logoUrl;
  final String? websiteUrl;

  @override
  List<Object?> get props => [id, name, logoUrl, websiteUrl];
}

/// A benefit as `GET /api/benefits` lists it.
///
/// There is deliberately no code or link value here: the reveal call is the
/// only place one exists in the app.
class CampusBenefit extends Equatable {
  const CampusBenefit({
    required this.id,
    required this.campusId,
    required this.section,
    required this.title,
    required this.redemptionType,
    this.category,
    this.description = const BenefitText(),
    this.terms = const BenefitText(),
    this.imageUrl,
    this.isFeatured = false,
    this.partner,
    this.publishEnd,
  });

  /// Parses one API item; null when it lacks an id, a campus or any title,
  /// so one bad item never takes the list down.
  static CampusBenefit? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = _text(json['id']);
    final campusId = _text(json['campusId']);
    final title = BenefitText.fromJson(json['title']);
    if (id == null || campusId == null) return null;
    if (title.nb == null && title.en == null) return null;
    final end = json['publishEnd'];
    return CampusBenefit(
      id: id,
      campusId: campusId,
      section: BenefitSection.values.firstWhere(
        (s) => s.name == json['section'],
        orElse: () => BenefitSection.member,
      ),
      category: _text(json['category']),
      title: title,
      description: BenefitText.fromJson(json['description']),
      terms: BenefitText.fromJson(json['terms']),
      imageUrl: _text(json['imageUrl']),
      isFeatured: json['isFeatured'] == true,
      partner: BenefitPartner.tryParse(json['partner']),
      publishEnd: end is String ? DateTime.tryParse(end) : null,
      redemptionType: BenefitRedemptionType.values.firstWhere(
        (t) => t.name == json['redemptionType'],
        orElse: () => BenefitRedemptionType.none,
      ),
    );
  }

  final String id;
  final String campusId;
  final BenefitSection section;
  final String? category;
  final BenefitText title;
  final BenefitText description;
  final BenefitText terms;
  final String? imageUrl;
  final bool isFeatured;
  final BenefitPartner? partner;
  final DateTime? publishEnd;
  final BenefitRedemptionType redemptionType;

  @override
  List<Object?> get props => [
    id,
    campusId,
    section,
    category,
    title,
    description,
    terms,
    imageUrl,
    isFeatured,
    partner,
    publishEnd,
    redemptionType,
  ];
}

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
