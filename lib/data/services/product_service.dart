import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart';

import '../../core/constants/app_constants.dart';
import '../../core/logging/app_logger.dart';
import '../../types/product_favorites.dart';
import '../models/product_model.dart';
import 'appwrite_service.dart';

class ProductService {
  static const String collectionId = 'products';
  static const String favoritesCollectionId = 'product_favorites';

  Future<List<ProductModel>> getLatestProducts({
    String? campusId,
    String? status = 'available',
    int limit = 10,
  }) async {
    final List<String> queries = [
      Query.orderDesc('\$createdAt'),
      Query.limit(limit),
    ];

    if (campusId != null) {
      queries.add(Query.equal('campus_id', campusId));
    }
    if (status != null) {
      queries.add(Query.equal('status', status));
    }

    AppLogger.info(
      '[PRODUCTS] Fetching latest Appwrite products',
      extra: {
        'database_id': AppConstants.databaseId,
        'table_id': collectionId,
        'campus_id': campusId,
        'status': status,
        'limit': limit,
        'queries': queries,
      },
    );

    final response = await db.listRows(
      databaseId: AppConstants.databaseId,
      tableId: collectionId,
      queries: queries,
    );
    final products = response.rows
        .map((doc) => ProductModel.fromMap(_rowData(doc)))
        .toList(growable: false);
    AppLogger.info(
      '[PRODUCTS] Latest Appwrite products loaded',
      extra: {
        'campus_id': campusId,
        'count': products.length,
        'total': response.total,
        'sample_ids': products.take(3).map((product) => product.id).toList(),
      },
    );
    return products;
  }

  Future<List<ProductModel>> listProducts({
    String? campusId,
    String? category,
    String? status,
    String? search,
    int limit = AppConstants.defaultPageSize,
    int offset = 0,
  }) async {
    final List<String> queries = [
      Query.limit(limit),
      Query.offset(offset),
      Query.orderDesc('\$createdAt'),
    ];
    if (campusId != null) queries.add(Query.equal('campus_id', campusId));
    if (category != null && category != 'all') {
      queries.add(Query.equal('category', category));
    }
    if (status != null) queries.add(Query.equal('status', status));
    if (search != null && search.trim().isNotEmpty) {
      queries.add(Query.search('description', search.trim()));
      queries.add(Query.search('name', search.trim()));
    }

    AppLogger.info(
      '[PRODUCTS] Listing Appwrite products',
      extra: {
        'database_id': AppConstants.databaseId,
        'table_id': collectionId,
        'campus_id': campusId,
        'category': category,
        'status': status,
        'search': search,
        'limit': limit,
        'offset': offset,
        'queries': queries,
      },
    );

    final response = await db.listRows(
      databaseId: AppConstants.databaseId,
      tableId: collectionId,
      queries: queries,
    );
    final products = response.rows
        .map((doc) => ProductModel.fromMap(_rowData(doc)))
        .toList(growable: false);
    AppLogger.info(
      '[PRODUCTS] Appwrite products loaded',
      extra: {
        'campus_id': campusId,
        'category': category,
        'status': status,
        'search': search,
        'count': products.length,
        'total': response.total,
        'sample_ids': products.take(3).map((product) => product.id).toList(),
      },
    );
    return products;
  }

  Future<ProductModel?> getProductById(String id) async {
    final doc = await db.getRow(
      databaseId: AppConstants.databaseId,
      tableId: collectionId,
      rowId: id,
    );
    return ProductModel.fromMap(_rowData(doc));
  }

  Future<ProductModel> createProduct({
    required ProductModel product,
    List<String> imagePaths = const [],
  }) async {
    final List<String> imageUrls = [];
    final List<String> fileIds = [];
    for (final path in imagePaths) {
      final fileId = await _uploadImage(path);
      final url = _publicFileUrl(AppConstants.productsBucketId, fileId);
      imageUrls.add(url);
      fileIds.add(fileId);
    }

    final data = product
        .copyWith(images: imageUrls, imageFileIds: fileIds)
        .toMap();
    final docId = ID.unique();

    final doc = await db.createRow(
      databaseId: AppConstants.databaseId,
      tableId: collectionId,
      rowId: docId,
      data: data,
    );
    return ProductModel.fromMap(_rowData(doc));
  }

  Future<ProductModel> updateProduct(ProductModel product) async {
    final doc = await db.updateRow(
      databaseId: AppConstants.databaseId,
      tableId: collectionId,
      rowId: product.id,
      data: product.toMap(),
    );
    return ProductModel.fromMap(_rowData(doc));
  }

  Future<void> markStatus({
    required String productId,
    required String status, // 'available' | 'sold' | 'reserved' | 'inactive'
  }) async {
    await db.updateRow(
      databaseId: AppConstants.databaseId,
      tableId: collectionId,
      rowId: productId,
      data: {'status': status},
    );
  }

  Future<void> incrementViewCount(String productId) async {
    try {
      await db.updateRow(
        databaseId: AppConstants.databaseId,
        tableId: collectionId,
        rowId: productId,
        data: {'view_count': Operator.increment(1)},
      );
    } catch (_) {
      // best effort
    }
  }

  Future<bool> isFavorited({
    required String userId,
    required String productId,
  }) async {
    final res = await db.listRows(
      databaseId: AppConstants.databaseId,
      tableId: favoritesCollectionId,
      queries: [
        Query.equal('user_id', userId),
        Query.equal('product', productId),
        Query.limit(1),
      ],
    );
    return res.rows.isNotEmpty;
  }

  Future<bool> toggleFavorite({
    required String userId,
    required String productId,
  }) async {
    final res = await db.listRows(
      databaseId: AppConstants.databaseId,
      tableId: favoritesCollectionId,
      queries: [
        Query.equal('user_id', userId),
        Query.equal('product', productId),
        Query.limit(1),
      ],
    );
    if (res.rows.isEmpty) {
      await db.createRow(
        databaseId: AppConstants.databaseId,
        tableId: favoritesCollectionId,
        rowId: ID.unique(),
        data: {'user_id': userId, 'product': productId},
      );
      await _bumpFavoriteCount(productId, 1);
      return true;
    } else {
      await db.deleteRow(
        databaseId: AppConstants.databaseId,
        tableId: favoritesCollectionId,
        rowId: res.rows.first.$id,
      );
      await _bumpFavoriteCount(productId, -1);
      return false;
    }
  }

  Future<List<ProductModel>> getUserFavoriteProducts({
    required String userId,
    String? campusId,
    String? category,
    int limit = AppConstants.defaultPageSize,
    int offset = 0,
  }) async {
    final List<String> queries = [
      Query.limit(limit),
      Query.offset(offset),
      Query.orderDesc('\$createdAt'),
      Query.equal('user_id', userId),
    ];

    final results = await db.listRows(
      databaseId: AppConstants.databaseId,
      tableId: favoritesCollectionId,
      queries: queries,
    );
    AppLogger.info(
      '[PRODUCTS] Listing favorite products',
      extra: {
        'user_id': userId,
        'campus_id': campusId,
        'category': category,
        'favorite_rows': results.rows.length,
        'total': results.total,
      },
    );

    final List<ProductModel> products = [];
    for (final favoriteRow in results.rows) {
      final favorite = ProductFavorites.fromMap(_rowData(favoriteRow));
      if (favorite.product == null) continue;

      final productData = favoriteRow.data['product'];
      if (productData is! Map<String, dynamic>) continue;

      try {
        final product = ProductModel.fromMap(productData);

        if (campusId != null && product.campusId != campusId) continue;
        if (category != null &&
            category != 'all' &&
            product.category != category) {
          continue;
        }
        if (product.status != 'available') continue;

        products.add(product);
      } catch (e) {
        continue;
      }
    }

    AppLogger.info(
      '[PRODUCTS] Favorite products resolved',
      extra: {
        'user_id': userId,
        'campus_id': campusId,
        'category': category,
        'count': products.length,
        'sample_ids': products.take(3).map((product) => product.id).toList(),
      },
    );
    return products;
  }

  Future<void> _bumpFavoriteCount(String productId, int delta) async {
    try {
      await db.updateRow(
        databaseId: AppConstants.databaseId,
        tableId: collectionId,
        rowId: productId,
        data: {
          'favorite_count': delta > 0
              ? Operator.increment(delta)
              : Operator.decrement(-delta, 0),
        },
      );
    } catch (_) {}
  }

  Future<String> _uploadImage(String filePath) async {
    final file = await storage.createFile(
      bucketId: AppConstants.productsBucketId,
      fileId: ID.unique(),
      file: InputFile.fromPath(path: filePath),
    );
    return file.$id;
  }

  String _publicFileUrl(String bucketId, String fileId) {
    final endpoint = client.endPoint;
    final projectId = client.config['project'];
    return '$endpoint/storage/buckets/$bucketId/files/$fileId/view?project=$projectId';
  }

  Map<String, dynamic> _rowData(Row row) => {
    ...row.data,
    '\$id': row.$id,
    '\$createdAt': row.$createdAt,
    '\$updatedAt': row.$updatedAt,
  };
}
