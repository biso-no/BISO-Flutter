import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/app_constants.dart';
import '../../core/logging/app_logger.dart';
import '../models/webshop_product_model.dart';

class WebshopService {
  Future<List<WebshopProduct>> listWebshopProducts({
    String? campusId,
    String? campusName,
    String? departmentId,
    int limit = 20,
    int page = 1,
  }) async {
    final Map<String, dynamic> body = {
      if (campusId != null && campusId.isNotEmpty) 'campusId': campusId,
      if ((campusId == null || campusId.isEmpty) &&
          campusName != null &&
          campusName.isNotEmpty)
        'campus': campusName,
      if (departmentId != null) 'departmentId': departmentId,
      'perPage': limit,
      'page': page,
    };

    final endpoint = '${AppConstants.apiUrl}/wc-products';
    final stopwatch = Stopwatch()..start();
    AppLogger.api(
      'Fetching webshop products from API',
      endpoint: endpoint,
      method: 'POST',
      extra: {
        'campus_name': campusName,
        'campus_id': campusId,
        'department_id': departmentId,
        'limit': limit,
        'page': page,
      },
    );

    final execution = await http.post(
      Uri.parse(endpoint),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    );
    stopwatch.stop();

    AppLogger.api(
      'Webshop products API response received',
      endpoint: endpoint,
      method: 'POST',
      statusCode: execution.statusCode,
      extra: {
        'campus_name': campusName,
        'campus_id': campusId,
        'duration_ms': stopwatch.elapsedMilliseconds,
        'body_length': execution.body.length,
        if (execution.statusCode != 200)
          'body_preview': _preview(execution.body),
      },
    );

    if (execution.statusCode != 200) {
      throw Exception(
        'Failed to load webshop products: HTTP ${execution.statusCode}',
      );
    }

    final Map<String, dynamic> payload = json.decode(execution.body);
    final List<dynamic> products =
        payload['products'] as List<dynamic>? ?? const <dynamic>[];
    final mapped = products
        .map((e) => WebshopProduct.fromFunctionMap(e as Map<String, dynamic>))
        .toList(growable: false);
    final filtered = _filterProducts(
      mapped,
      campusId: campusId,
      departmentId: departmentId,
    );
    AppLogger.info(
      '[WEBSHOP] Parsed API products response',
      extra: {
        'campus_name': campusName,
        'campus_id': campusId,
        'raw_count': mapped.length,
        'count': filtered.length,
        'pagination': payload['pagination']?.toString(),
        'sample_ids': filtered
            .take(3)
            .map((product) => product.id.toString())
            .toList(),
        'sample_campus_ids': filtered
            .take(3)
            .map((product) => product.campusId)
            .toList(),
      },
    );
    return filtered;
  }

  String _preview(String body) {
    const maxLength = 500;
    if (body.length <= maxLength) return body;
    return '${body.substring(0, maxLength)}...';
  }

  List<WebshopProduct> _filterProducts(
    List<WebshopProduct> products, {
    required String? campusId,
    required String? departmentId,
  }) {
    return products
        .where((product) {
          if (campusId != null &&
              campusId.isNotEmpty &&
              product.campusId != null &&
              product.campusId != campusId) {
            return false;
          }
          if (departmentId != null &&
              departmentId.isNotEmpty &&
              product.departmentId != null &&
              product.departmentId != departmentId) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }
}
