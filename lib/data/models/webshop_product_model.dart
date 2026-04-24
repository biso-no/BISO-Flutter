import 'package:equatable/equatable.dart';

class WebshopProduct extends Equatable {
  final int id;
  final String name;
  final String? campusId;
  final String? campusLabel;
  final String? departmentId;
  final String? departmentLabel;
  final List<String> images;
  final String price; // Woo returns price as string
  final String salePrice;
  final String? description;
  final String? url;

  const WebshopProduct({
    required this.id,
    required this.name,
    required this.images,
    required this.price,
    required this.salePrice,
    this.campusId,
    this.campusLabel,
    this.departmentId,
    this.departmentLabel,
    this.description,
    this.url,
  });

  factory WebshopProduct.fromFunctionMap(Map<String, dynamic> map) {
    final metadata = _metadataMap(map['meta_data']);
    final campusId = _stringValue(
      map['campus_id'] ?? map['campusId'] ?? metadata['campus'],
    );
    MapEntry<String, dynamic>? departmentEntry;
    for (final entry in metadata.entries) {
      if (entry.key.startsWith('department_') &&
          !entry.key.startsWith('_department_')) {
        departmentEntry = entry;
        break;
      }
    }
    final departmentId = _stringValue(
      map['department_id'] ?? map['departmentId'] ?? departmentEntry?.value,
    );

    return WebshopProduct(
      id: (map['id'] ?? 0) as int,
      name: (map['name'] ?? '') as String,
      images: _parseImages(map['images']),
      price: (map['price'] ?? '') as String,
      salePrice: (map['sale_price'] ?? '') as String,
      campusId: campusId,
      campusLabel:
          _labelFromObject(map['campus']) ?? _campusLabelFromId(campusId),
      departmentId: departmentId,
      departmentLabel: _labelFromObject(map['department']),
      description: map['description'] as String?,
      url: (map['url'] ?? map['permalink']) as String?,
    );
  }

  bool get hasSale => salePrice.isNotEmpty && salePrice != '0';

  @override
  List<Object?> get props => [
    id,
    name,
    campusId,
    campusLabel,
    departmentId,
    departmentLabel,
    images,
    price,
    salePrice,
    url,
  ];

  static Map<String, dynamic> _metadataMap(dynamic value) {
    if (value is! List) return const <String, dynamic>{};
    return {
      for (final item in value)
        if (item is Map<String, dynamic> && item['key'] != null)
          item['key'].toString(): item['value'],
    };
  }

  static List<String> _parseImages(dynamic value) {
    if (value is! List) return const <String>[];
    return value
        .map((item) {
          if (item is String) return item;
          if (item is Map<String, dynamic>) {
            return (item['src'] ?? item['url'] ?? item['thumbnail'])
                ?.toString();
          }
          return null;
        })
        .whereType<String>()
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static String? _labelFromObject(dynamic value) {
    if (value is Map<String, dynamic>) {
      return _stringValue(value['label'] ?? value['name']);
    }
    return null;
  }

  static String? _stringValue(dynamic value) {
    final stringValue = value?.toString().trim();
    return stringValue == null || stringValue.isEmpty ? null : stringValue;
  }

  static String? _campusLabelFromId(String? campusId) {
    switch (campusId) {
      case '1':
        return 'Oslo';
      case '2':
        return 'Bergen';
      case '3':
        return 'Trondheim';
      case '4':
        return 'Stavanger';
      default:
        return null;
    }
  }
}
