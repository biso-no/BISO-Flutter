import 'package:appwrite/appwrite.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/appwrite_row.dart';
import '../models/webshop_product_model.dart';
import 'appwrite_service.dart';

class WebshopService {
  static const String collectionId = 'webshop_products';

  /// The relations every webshop products read selects, list and by-id
  /// alike: nested relations are only returned when explicitly selected, so
  /// a new relation must be added here to reach both reads. The count read
  /// intentionally selects only `$id` to avoid fetching whole rows and their
  /// expanded relations just to read one integer.
  static const List<String> _productSelect = [
    '*',
    'translation_refs.*',
    'variations.*',
    'custom_fields.*',
  ];

  /// The filter clauses every webshop products read shares, list and count
  /// alike.
  ///
  /// Locale is intentionally absent: filtering `translation_refs.locale`
  /// narrows parent rows rather than the nested array, which would hide
  /// products that lack that locale. Locale is resolved client-side instead.
  static List<String> _productFilters({
    String? campusId,
    String? search,
  }) {
    final queries = <String>[Query.equal('status', 'published')];

    if (campusId != null && campusId.isNotEmpty) {
      queries.add(Query.equal('campus_id', campusId));
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
  }) {
    return [
      ..._productFilters(campusId: campusId, search: search),
      // Nested relations are only returned when explicitly selected.
      Query.select(_productSelect),
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
  }) async {
    final response = await db.listRows(
      databaseId: AppConstants.databaseId,
      tableId: collectionId,
      queries: buildProductQueries(
        campusId: campusId,
        limit: limit,
        offset: offset,
        search: search,
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

  /// Builds the query list for a by-id webshop product read.
  ///
  /// Shares [_productSelect] and [_productFilters] with [buildProductQueries]
  /// and [buildProductCountQueries]: a relation or filter added to one and
  /// not the other would leave reads silently missing it.
  static List<String> buildProductByIdQueries(String id) {
    return [
      Query.equal(r'$id', id),
      ..._productFilters(),
      Query.select(_productSelect),
      Query.limit(1),
    ];
  }

  /// Reads a single published webshop product by its Appwrite row id.
  Future<WebshopProduct?> getProductById(String id, {String locale = 'no'}) async {
    final response = await db.listRows(
      databaseId: AppConstants.databaseId,
      tableId: collectionId,
      queries: buildProductByIdQueries(id),
    );
    if (response.rows.isEmpty) return null;
    return WebshopProduct.fromAppwriteRow(
      rowData(response.rows.first),
      locale: locale,
    );
  }
}
