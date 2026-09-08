import 'package:appwrite/appwrite.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/appwrite_row.dart';
import '../models/webshop_product_model.dart';
import 'appwrite_service.dart';

class WebshopService {
  static const String collectionId = 'webshop_products';

  /// The filter clauses every webshop products read shares, list and count
  /// alike.
  ///
  /// Locale is intentionally absent: filtering `translation_refs.locale`
  /// narrows parent rows rather than the nested array, which would hide
  /// products that lack that locale. Locale is resolved client-side instead.
  static List<String> _productFilters({
    String? campusId,
    String? search,
    String? category,
  }) {
    final queries = <String>[Query.equal('status', 'published')];

    if (campusId != null && campusId.isNotEmpty) {
      queries.add(Query.equal('campus_id', campusId));
    }
    if (category != null && category.isNotEmpty) {
      queries.add(Query.equal('category', category));
    }

    final term = search?.trim() ?? '';
    if (term.isNotEmpty) {
      queries.add(Query.contains('translation_refs.title', [term]));
    }

    return queries;
  }

  /// Builds the query list for a webshop products read.
  static List<String> buildProductQueries({
    String? campusId,
    int limit = 20,
    int offset = 0,
    String? search,
    String? category,
  }) {
    return [
      ..._productFilters(campusId: campusId, search: search, category: category),
      // Nested relations are only returned when explicitly selected.
      Query.select([
        '*',
        'translation_refs.*',
        'variations.*',
        'custom_fields.*',
      ]),
      Query.orderDesc(r'$createdAt'),
      Query.limit(limit),
      Query.offset(offset),
    ];
  }

  /// Builds the query list for a count-only webshop products read.
  ///
  /// Same filters as [buildProductQueries], but selects just `$id` and asks
  /// for a single row: the caller reads `total`, never the rows, and
  /// Appwrite's `total` is the full match count independent of `limit`.
  /// Inheriting `select(['*', 'translation_refs.*', ...])` here would fetch
  /// whole rows plus their expanded relations to read one integer.
  static List<String> buildProductCountQueries({String? campusId}) {
    return [
      ..._productFilters(campusId: campusId),
      Query.select([r'$id']),
      Query.limit(1),
    ];
  }

  /// Reads webshop products directly from Appwrite, with server-side search
  /// and nested translations/variations/custom fields resolved client-side
  /// via [WebshopProduct.fromAppwriteRow].
  Future<List<WebshopProduct>> listProducts({
    String? campusId,
    String locale = 'no',
    int limit = 20,
    int offset = 0,
    String? search,
    String? category,
  }) async {
    final response = await db.listRows(
      databaseId: AppConstants.databaseId,
      tableId: collectionId,
      queries: buildProductQueries(
        campusId: campusId,
        limit: limit,
        offset: offset,
        search: search,
        category: category,
      ),
    );

    return response.rows
        .map((row) => WebshopProduct.fromAppwriteRow(rowData(row), locale: locale))
        .toList(growable: false);
  }

  /// How many webshop products match the same filters [listProducts] uses.
  Future<int> countProducts({String? campusId}) async {
    final response = await db.listRows(
      databaseId: AppConstants.databaseId,
      tableId: collectionId,
      queries: buildProductCountQueries(campusId: campusId),
    );
    return response.total;
  }

  /// Reads a single published webshop product by its Appwrite row id.
  Future<WebshopProduct?> getProductById(String id, {String locale = 'no'}) async {
    final response = await db.listRows(
      databaseId: AppConstants.databaseId,
      tableId: collectionId,
      queries: [
        Query.equal(r'$id', id),
        Query.equal('status', 'published'),
        Query.select([
          '*',
          'translation_refs.*',
          'variations.*',
          'custom_fields.*',
        ]),
        Query.limit(1),
      ],
    );
    if (response.rows.isEmpty) return null;
    return WebshopProduct.fromAppwriteRow(
      rowData(response.rows.first),
      locale: locale,
    );
  }
}
