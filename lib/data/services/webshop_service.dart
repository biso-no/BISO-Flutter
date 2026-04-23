import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/app_constants.dart';
import '../models/webshop_product_model.dart';

class WebshopService {
  Future<List<WebshopProduct>> listWebshopProducts({
    required String campusName,
    String? departmentId,
    int limit = 20,
    int page = 1,
  }) async {
    final Map<String, dynamic> body = {
      // Function supports both `campus` and `campusId`; we send readable name to satisfy mapping
      'campus': campusName,
      if (departmentId != null) 'departmentId': departmentId,
      'perPage': limit,
      'page': page,
    };

    final execution = await http.post(
      Uri.parse('${AppConstants.apiUrl}/wc-products'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    );

    if (execution.statusCode != 200) {
      throw Exception('Failed to load webshop products: HTTP ${execution.statusCode}');
    }

    final Map<String, dynamic> payload = json.decode(execution.body);
    final List<dynamic> products = payload['products'] as List<dynamic>? ?? const <dynamic>[];
    return products
        .map((e) => WebshopProduct.fromFunctionMap(e as Map<String, dynamic>))
        .toList(growable: false);
  }
}


