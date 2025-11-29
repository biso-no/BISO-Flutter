import 'package:appwrite/appwrite.dart';

import '../../core/constants/app_constants.dart';
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

    final response = await db.listRows(
      databaseId: AppConstants.databaseId,
      tableId: collectionId,
      queries: queries,
    );
    return response.rows
        .map((doc) {
          final map = Map<String, dynamic>.from(doc.data);
          map['\$id'] = doc.$id;
          return ProductModel.fromMap(map);
        })
        .toList(growable: false);
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
    if (category != null && category != 'all') queries.add(Query.equal('category', category));      
    if (status != null) queries.add(Query.equal('status', status));
    if (search != null && search.trim().isNotEmpty) {
      queries.add(Query.search('description', search.trim()));
      queries.add(Query.search('name', search.trim()));
    }

    final response = await db.listRows(
      databaseId: AppConstants.databaseId,
      tableId: collectionId,
      queries: queries,
    );
    return response.rows
        .map((doc) {
          final map = Map<String, dynamic>.from(doc.data);
          map['\$id'] = doc.$id;
          return ProductModel.fromMap(map);
        })
        .toList(growable: false);
  }

  Future<ProductModel?> getProductById(String id) async {
    final doc = await db.getRow(
      databaseId: AppConstants.databaseId,
      tableId: collectionId,
      rowId: id,
    );
    final map = Map<String, dynamic>.from(doc.data);
    map['\$id'] = doc.$id;
    return ProductModel.fromMap(map);
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
    final map = Map<String, dynamic>.from(doc.data);
    map['\$id'] = doc.$id;
    return ProductModel.fromMap(map);
  }

  Future<ProductModel> updateProduct(ProductModel product) async {
    final doc = await db.updateRow(
      databaseId: AppConstants.databaseId,
      tableId: collectionId,
      rowId: product.id,
      data: product.toMap(),
    );
    final map = Map<String, dynamic>.from(doc.data);
    map['\$id'] = doc.$id;
    return ProductModel.fromMap(map);
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
      final current = await db.getRow(
        databaseId: AppConstants.databaseId,
        tableId: collectionId,
        rowId: productId,
      );
      final count = (current.data['view_count'] ?? 0) as int;
      await db.updateRow(
        databaseId: AppConstants.databaseId,
        tableId: collectionId,
        rowId: productId,
        data: {'view_count': count + 1},
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

    // Extract products from the relationship field and filter them
    final List<ProductModel> products = [];
    for (final favorite in results.rows) {
      final favoriteMap = Map<String, dynamic>.from(favorite.data);
      favoriteMap['\$id'] = favorite.$id;
      final productData = favoriteMap['product'];
      if (productData != null && productData is Map<String, dynamic>) {
        try {
          final product = ProductModel.fromMap(productData);

          // Apply campus filter
          if (campusId != null && product.campusId != campusId) continue;

          // Apply category filter
          if (category != null &&
              category != 'all' &&
              product.category != category) {
            continue;
          }

          // Only include available products
          if (product.status != 'available') continue;

          products.add(product);
        } catch (e) {
          // Skip malformed product data
          continue;
        }
      }
    }

    return products;
  }

  Future<void> _bumpFavoriteCount(String productId, int delta) async {
    try {
      final current = await db.getRow(
        databaseId: AppConstants.databaseId,
        tableId: collectionId,
        rowId: productId,
      );
      final count = (current.data['favorite_count'] ?? 0) as int;
      final int newCount = count + delta;
      final int safeCount = newCount < 0 ? 0 : newCount;
      await db.updateRow(
        databaseId: AppConstants.databaseId,
        tableId: collectionId,
        rowId: productId,
        data: {'favorite_count': safeCount},
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
}
