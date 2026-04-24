import 'dart:async';

import 'package:appwrite/appwrite.dart';

import '../models/entur_models.dart';
import 'appwrite_service.dart';

class EnturService {
  TablesDB get _databases => db;
  Realtime get _realtime => realtime;

  static const String enturDatabaseId = 'entur';
  static const String departuresCollectionId = 'departures';
  static const String stopPlacesCollectionId = 'stop_places';

  RealtimeSubscription? _subscription;
  final StreamController<EnturDepartureBoard?> _boardController =
      StreamController<EnturDepartureBoard?>.broadcast();

  Stream<EnturDepartureBoard?> get boardStream => _boardController.stream;

  Future<List<StopPlaceModel>> getStopPlacesForCampus(String campusId) async {
    final response = await _databases.listRows(
      databaseId: enturDatabaseId,
      tableId: stopPlacesCollectionId,
      queries: [
        Query.equal('campus_id', campusId),
        Query.equal('enabled', true),
        Query.orderAsc('name'),
      ],
    );
    return response.rows
        .map((doc) => StopPlaceModel.fromMap(doc.data))
        .toList();
  }

  Future<EnturDepartureBoard?> getDeparturesByStopPlaceId(
    String stopPlaceId,
  ) async {
    try {
      final doc = await _databases.getRow(
        databaseId: enturDatabaseId,
        tableId: departuresCollectionId,
        rowId: sanitizeDocumentId(stopPlaceId),
      );
      return EnturDepartureBoard.fromDocument(doc.data);
    } on AppwriteException catch (e) {
      if (e.code == 404) return null;
      rethrow;
    }
  }

  void subscribeToDepartures(String stopPlaceId) {
    _subscription?.close();
    final channel = Channel.tablesdb(
      enturDatabaseId,
    ).table(departuresCollectionId).row(sanitizeDocumentId(stopPlaceId));
    _subscription = _realtime.subscribe([channel.toString()]);
    _subscription!.stream.listen((event) {
      final payload = event.payload;
      try {
        final board = EnturDepartureBoard.fromDocument(payload);
        _boardController.add(board);
      } catch (_) {
        _boardController.add(null);
      }
    });
  }

  void dispose() {
    _subscription?.close();
    _boardController.close();
  }
}
