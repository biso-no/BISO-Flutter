import 'package:appwrite/appwrite.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/logging/print_migration.dart';

import '../../core/constants/app_constants.dart';
import '../models/campus_model.dart';
import '../models/campus_data_model.dart';
import '../models/campus_location_model.dart';
import '../models/department_board_model.dart';
import '../models/weather_model.dart' as wm;
import 'event_service.dart';
import 'job_service.dart';
import 'appwrite_service.dart';
import 'weather_service.dart';

class CampusService {
  static const String campusCollectionId = AppConstants.campusesCollectionId;
  static const String campusDataCollectionId = 'campus_data';
  static const String departmentBoardCollectionId = 'departmentBoard';

  // Cache keys and duration
  static const String _cacheKeyCampuses = 'cached_campuses_v1';
  static const String _cacheKeyCampusesUpdatedAt = 'cached_campuses_updated_at_v1';
  static const Duration _cacheTtl = Duration(hours: 2);

  Future<List<CampusModel>> getAllCampuses() async {
    final stopwatch = Stopwatch()..start();
    logInfo('CampusService.getAllCampuses: start');
    try {
      final apiTimer = Stopwatch()..start();
      final results = await db.listRows(
        databaseId: AppConstants.databaseId,
        tableId: campusCollectionId,
        queries: [
          Query.orderAsc('name'),
          Query.select(['\$id', 'name']),
        ],
      );
      apiTimer.stop();
      logInfo('CampusService.getAllCampuses: listDocuments completed', context: {
        'elapsed_ms': apiTimer.elapsedMilliseconds,
        'total_documents': results.total,
      });

      // Build all campus models in parallel
      final buildStart = Stopwatch()..start();
      final futures = results.rows.map((doc) async {
        final perBuildTimer = Stopwatch()..start();
        final campus = await _buildCampusModel(doc.data);
        perBuildTimer.stop();
        if (campus != null) {
          logInfo('CampusService.getAllCampuses: built campus', context: {
            'campus_id': campus.id,
            'campus_name': campus.name,
            'elapsed_ms': perBuildTimer.elapsedMilliseconds,
          });
        }
        return campus;
      }).toList(growable: false);

      final built = await Future.wait(futures);
      final campuses = built.whereType<CampusModel>().toList(growable: false);
      
      // Sort campuses: campus with ID '5' should always be last, others alphabetically
      campuses.sort((a, b) {
        // If campus '5' is involved, handle special ordering
        if (a.id == '5') return 1; // Campus '5' goes to the end
        if (b.id == '5') return -1; // Campus '5' goes to the end
        
        // For all other campuses, maintain alphabetical order
        return a.name.compareTo(b.name);
      });
      
      buildStart.stop();
      logInfo('CampusService.getAllCampuses: all campus builds completed', context: {
        'elapsed_ms': buildStart.elapsedMilliseconds,
        'count': campuses.length,
      });

      // Write to cache on success
      final cacheWriteTimer = Stopwatch()..start();
      await _writeCachedCampuses(campuses);
      cacheWriteTimer.stop();
      logInfo('CampusService.getAllCampuses: cache write done', context: {
        'elapsed_ms': cacheWriteTimer.elapsedMilliseconds,
        'campus_count': campuses.length,
      });
      stopwatch.stop();
      logInfo('CampusService.getAllCampuses: completed', context: {
        'total_elapsed_ms': stopwatch.elapsedMilliseconds,
      });
      return campuses;
    } catch (e) {
      stopwatch.stop();
      logError('CampusService.getAllCampuses: error', error: e, context: {
        'total_elapsed_ms': stopwatch.elapsedMilliseconds,
      });
      // Fallback to cache if Appwrite fails
      final cacheReadTimer = Stopwatch()..start();
      final cached = await _readCachedCampuses();
      cacheReadTimer.stop();
      logWarning('CampusService.getAllCampuses: using cache due to error', context: {
        'cached_count': cached.length,
        'cache_read_ms': cacheReadTimer.elapsedMilliseconds,
      });
      if (cached.isNotEmpty) return cached;
      return <CampusModel>[];
    }
  }

  // Lightweight fetch for campus switcher: id, name, address (from campusData.location), optional weather
  Future<List<CampusModel>> getSwitcherCampuses({bool includeWeather = true}) async {
    final stopwatch = Stopwatch()..start();
    logInfo('CampusService.getSwitcherCampuses: start', context: {
      'include_weather': includeWeather,
    });
    try {
      final apiTimer = Stopwatch()..start();
      final results = await db.listRows(
        databaseId: AppConstants.databaseId,
        tableId: campusCollectionId,
        queries: [
          Query.orderAsc('name'),
          Query.select(['\$id', 'name']),
        ],
      );
      apiTimer.stop();
      logInfo('CampusService.getSwitcherCampuses: listDocuments completed', context: {
        'elapsed_ms': apiTimer.elapsedMilliseconds,
        'total_documents': results.total,
      });

      final futures = results.rows.map((doc) async {
        final campusDoc = doc.data;
        final String id = campusDoc['\$id']?.toString() ?? '';
        final String name = campusDoc['name']?.toString() ?? '';

        // Try to get location from embedded campusData; otherwise fetch minimal location
        String locationRaw = '';
        final dynamic campusDataRef = campusDoc['campusData'];
        if (campusDataRef is Map<String, dynamic>) {
          locationRaw = campusDataRef['location']?.toString() ?? '';
        } else if (campusDataRef is String && campusDataRef.isNotEmpty) {
          locationRaw = await _getCampusDataLocation(campusDataRef);
        }

        final WeatherData? weather = includeWeather
            ? await _getWeatherForCampusName(name)
            : null;

        return CampusModel(
          id: id,
          name: name,
          description: '',
          location: locationRaw,
          imageUrl: '',
          heroImageUrl: '',
          weather: weather,
          stats: const CampusStats(),
          metadata: const {},
        );
      }).toList(growable: false);

      final campuses = (await Future.wait(futures))
          .whereType<CampusModel>()
          .toList(growable: false);
      
      // Sort campuses: campus with ID '5' should always be last, others alphabetically
      campuses.sort((a, b) {
        // If campus '5' is involved, handle special ordering
        if (a.id == '5') return 1; // Campus '5' goes to the end
        if (b.id == '5') return -1; // Campus '5' goes to the end
        
        // For all other campuses, maintain alphabetical order
        return a.name.compareTo(b.name);
      });
      
      stopwatch.stop();
      logInfo('CampusService.getSwitcherCampuses: completed', context: {
        'total_elapsed_ms': stopwatch.elapsedMilliseconds,
        'count': campuses.length,
      });
      return campuses;
    } catch (e) {
      stopwatch.stop();
      logError('CampusService.getSwitcherCampuses: error', error: e, context: {
        'total_elapsed_ms': stopwatch.elapsedMilliseconds,
      });
      // Fallback to cache (may include richer data)
      final cached = await _readCachedCampuses();
      return cached;
    }
  }

  // Minimal campus by ID for switcher
  Future<CampusModel?> getCampusByIdLite(String campusId, {bool includeWeather = true}) async {
    final stopwatch = Stopwatch()..start();
    logInfo('CampusService.getCampusByIdLite: start', context: {
      'campus_id': campusId,
      'include_weather': includeWeather,
    });
    try {
      final apiTimer = Stopwatch()..start();
      final document = await db.getRow(
        databaseId: AppConstants.databaseId,
        tableId: campusCollectionId,
        rowId: campusId,
        queries: [
          Query.select(['\$id', 'name']),
        ],
      );
      apiTimer.stop();
      logInfo('CampusService.getCampusByIdLite: getDocument completed', context: {
        'elapsed_ms': apiTimer.elapsedMilliseconds,
      });

      final data = document.data;
      final String id = data['\$id']?.toString() ?? campusId;
      final String name = data['name']?.toString() ?? '';

      String locationRaw = '';
      final dynamic campusDataRef = data['campusData'];
      if (campusDataRef is Map<String, dynamic>) {
        locationRaw = campusDataRef['location']?.toString() ?? '';
      } else if (campusDataRef is String && campusDataRef.isNotEmpty) {
        locationRaw = await _getCampusDataLocation(campusDataRef);
      }

      final WeatherData? weather = includeWeather
          ? await _getWeatherForCampusName(name)
          : null;

      final model = CampusModel(
        id: id,
        name: name,
        description: '',
        location: locationRaw,
        imageUrl: '',
        heroImageUrl: '',
        weather: weather,
        stats: const CampusStats(),
        metadata: const {},
      );
      stopwatch.stop();
      logInfo('CampusService.getCampusByIdLite: completed', context: {
        'total_elapsed_ms': stopwatch.elapsedMilliseconds,
      });
      return model;
    } catch (e) {
      stopwatch.stop();
      logError('CampusService.getCampusByIdLite: error', error: e, context: {
        'campus_id': campusId,
        'total_elapsed_ms': stopwatch.elapsedMilliseconds,
      });
      // Fallback to cache
      final cached = await _readCachedCampuses();
      try {
        return cached.firstWhere((c) => c.id == campusId);
      } catch (_) {
        return null;
      }
    }
  }

  // Minimal fetch of campus_data.location only
  Future<String> _getCampusDataLocation(String campusDataId) async {
    try {
      final document = await db.getRow(
        databaseId: AppConstants.databaseId,
        tableId: campusDataCollectionId,
        rowId: campusDataId,
      );
      final data = document.data;
      final locationData = data['location']?.toString() ?? '';
      
      // Parse the location data to extract address
      if (locationData.isNotEmpty) {
        try {
          final location = CampusLocationModel.fromString(locationData);
          return location.address;
        } catch (e) {
          // If parsing fails, return the raw string
          return locationData;
        }
      }
      
      return '';
    } catch (e) {
      return '';
    }
  }

  Future<CampusModel?> getCampusById(String campusId) async {
    final stopwatch = Stopwatch()..start();
    logInfo('CampusService.getCampusById: start', context: {
      'campus_id': campusId,
    });
    try {
      final apiTimer = Stopwatch()..start();
      final document = await db.getRow(
        databaseId: AppConstants.databaseId,
        tableId: campusCollectionId,
        rowId: campusId,
        queries: [
          Query.select(['\$id', 'name']),
        ],
      );
      apiTimer.stop();
      logInfo('CampusService.getCampusById: getDocument completed', context: {
        'elapsed_ms': apiTimer.elapsedMilliseconds,
        'has_data': document.data.isNotEmpty,
      });

      final buildTimer = Stopwatch()..start();
      final model = await _buildCampusModel(document.data);
      buildTimer.stop();
      logInfo('CampusService.getCampusById: model built', context: {
        'elapsed_ms': buildTimer.elapsedMilliseconds,
        'campus_id': model?.id,
      });
      stopwatch.stop();
      logInfo('CampusService.getCampusById: completed', context: {
        'total_elapsed_ms': stopwatch.elapsedMilliseconds,
      });
      return model;
    } catch (e) {
      stopwatch.stop();
      logError('CampusService.getCampusById: error', error: e, context: {
        'campus_id': campusId,
        'total_elapsed_ms': stopwatch.elapsedMilliseconds,
      });
      // Fallback to cache
      final cacheReadTimer = Stopwatch()..start();
      final cached = await _readCachedCampuses();
      cacheReadTimer.stop();
      logWarning('CampusService.getCampusById: using cache due to error', context: {
        'cache_read_ms': cacheReadTimer.elapsedMilliseconds,
      });
      try {
        return cached.firstWhere((c) => c.id == campusId);
      } catch (_) {
        return null;
      }
    }
  }

  Future<CampusModel?> _buildCampusModel(Map<String, dynamic> campusDoc) async {
    final stopwatch = Stopwatch()..start();
    logInfo('CampusService._buildCampusModel: start', context: {
      'doc_id': campusDoc['\$id'],
      'name': campusDoc['name'],
    });
    try {
      // Get campus data relationship
      CampusDataModel? campusData;
      List<DepartmentBoardModel> departmentBoard = [];

      if (campusDoc['campusData'] != null) {
        final campusDataId = campusDoc['campusData'] is String 
            ? campusDoc['campusData']
            : campusDoc['campusData']['\$id'];
        
        if (campusDataId != null) {
          final campusDataTimer = Stopwatch()..start();
          campusData = await getCampusData(campusDataId);
          campusDataTimer.stop();
          logInfo('CampusService._buildCampusModel: campusData loaded', context: {
            'elapsed_ms': campusDataTimer.elapsedMilliseconds,
            'campusDataId': campusDataId,
            'hasData': campusData != null,
          });
          if (campusData != null) {
            departmentBoard = campusData.departmentBoard;
          }
        }
      } else {
        // Fallback: campus_data has same ID as campus
        final campusDataTimer = Stopwatch()..start();
        campusData = await getCampusData(campusDoc['\$id']);
        campusDataTimer.stop();
        logInfo('CampusService._buildCampusModel: campusData fallback by campusId', context: {
          'elapsed_ms': campusDataTimer.elapsedMilliseconds,
          'campusId': campusDoc['\$id'],
          'hasData': campusData != null,
        });
        if (campusData != null) {
          departmentBoard = campusData.departmentBoard;
        }
      }

      // Build campus model with data from both collections
      final weatherTimer = Stopwatch()..start();
      final weather = await _getWeatherForCampusName(campusDoc['name']);
      weatherTimer.stop();
      logInfo('CampusService._buildCampusModel: weather fetched', context: {
        'elapsed_ms': weatherTimer.elapsedMilliseconds,
        'name': campusDoc['name'],
        'hasWeather': weather != null,
      });

      final statsTimer = Stopwatch()..start();
      final stats = await _getCampusStats(campusDoc['\$id']);
      statsTimer.stop();
      logInfo('CampusService._buildCampusModel: stats computed', context: {
        'elapsed_ms': statsTimer.elapsedMilliseconds,
        'campus_id': campusDoc['\$id'],
      });

      final model = CampusModel(
        id: campusDoc['\$id'] ?? '',
        name: campusDoc['name'] ?? '',
        description: campusData?.description ?? '',
        location: campusData?.location?.address ?? '',
        imageUrl: 'assets/images/${campusDoc['name']?.toLowerCase()}_campus.jpg',
        heroImageUrl: 'assets/images/${campusDoc['name']?.toLowerCase()}_hero.jpg',
        benefits: campusData?.socialNetwork ?? [],
        studentBenefits: campusData?.studentBenefits ?? [],
        businessBenefits: campusData?.businessBenefits ?? [],
        careerAdvantages: campusData?.careerAdvantages ?? [],
        contactEmail: campusData?.location?.email ?? 'contact@bi.no',
        contactAddress: campusData?.location?.address,
        weather: weather,
        stats: stats,
        metadata: {
          'departmentBoard': departmentBoard.map((board) => board.toMap()).toList(),
          'safety': campusData?.safety ?? [],
        },
      );
      stopwatch.stop();
      logInfo('CampusService._buildCampusModel: completed', context: {
        'elapsed_ms': stopwatch.elapsedMilliseconds,
        'campus_id': model.id,
      });
      return model;
    } catch (e) {
      stopwatch.stop();
      logError('CampusService._buildCampusModel: error', error: e, context: {
        'elapsed_ms': stopwatch.elapsedMilliseconds,
        'doc_id': campusDoc['\$id'],
      });
      return null;
    }
  }

  Future<CampusDataModel?> getCampusData(String campusDataId) async {
    final stopwatch = Stopwatch()..start();
    logInfo('CampusService._getCampusData: start', context: {
      'campusDataId': campusDataId,
    });
    try {
      final apiTimer = Stopwatch()..start();
      final document = await db.getRow(
        databaseId: AppConstants.databaseId,
        tableId: campusDataCollectionId,
        rowId: campusDataId,
      );
      apiTimer.stop();
      logInfo('CampusService._getCampusData: document fetched', context: {
        'elapsed_ms': apiTimer.elapsedMilliseconds,
        'has_data': document.data.isNotEmpty,
      });
      final campusData = CampusDataModel.fromMap(document.data);

      // Fetch department board members
      List<DepartmentBoardModel> departmentBoard = [];
      if (document.data['departmentBoard'] != null) {
        final boardTimer = Stopwatch()..start();
        departmentBoard = await _getDepartmentBoard(document.data['departmentBoard']);
        boardTimer.stop();
        logInfo('CampusService._getCampusData: department board fetched', context: {
          'elapsed_ms': boardTimer.elapsedMilliseconds,
          'count': departmentBoard.length,
        });
      }

      final result = campusData.copyWith(departmentBoard: departmentBoard);
      stopwatch.stop();
      logInfo('CampusService._getCampusData: completed', context: {
        'total_elapsed_ms': stopwatch.elapsedMilliseconds,
      });
      return result;
    } catch (e) {
      stopwatch.stop();
      logError('CampusService._getCampusData: error', error: e, context: {
        'total_elapsed_ms': stopwatch.elapsedMilliseconds,
      });
      return null;
    }
  }

  Future<List<DepartmentBoardModel>> _getDepartmentBoard(dynamic departmentBoardRef) async {
    final stopwatch = Stopwatch()..start();
    logInfo('CampusService._getDepartmentBoard: start');
    try {
      List<String> boardIds = [];
      
      if (departmentBoardRef is List) {
        boardIds = departmentBoardRef.map((ref) => 
          ref is String ? ref : ref['\$id'].toString()).toList();
      } else if (departmentBoardRef is String) {
        boardIds = [departmentBoardRef];
      }

      final List<DepartmentBoardModel> boardMembers = [];
      
      for (final boardId in boardIds) {
        try {
          final apiTimer = Stopwatch()..start();
          final document = await db.getRow(
            databaseId: AppConstants.databaseId,
            tableId: departmentBoardCollectionId,
            rowId: boardId,
          );
          apiTimer.stop();
          logInfo('CampusService._getDepartmentBoard: member fetched', context: {
            'elapsed_ms': apiTimer.elapsedMilliseconds,
            'board_id': boardId,
          });
          boardMembers.add(DepartmentBoardModel.fromMap(document.data));
        } catch (e) {
          // Skip individual failures
          continue;
        }
      }

      stopwatch.stop();
      logInfo('CampusService._getDepartmentBoard: completed', context: {
        'total_elapsed_ms': stopwatch.elapsedMilliseconds,
        'count': boardMembers.length,
      });
      return boardMembers;
    } catch (e) {
      stopwatch.stop();
      logError('CampusService._getDepartmentBoard: error', error: e, context: {
        'total_elapsed_ms': stopwatch.elapsedMilliseconds,
      });
      return [];
    }
  }

  Future<CampusStats> _getCampusStats(String campusId) async {
    final stopwatch = Stopwatch()..start();
    logInfo('CampusService._getCampusStats: start', context: {
      'campus_id': campusId,
    });
    try {
      // Run all sub-queries in parallel
      final eventService = EventService();
      final jobService = JobService();

      Future<int> fetchEvents() async {
        try {
          final eventsTimer = Stopwatch()..start();
          final count = await eventService.getEventsTotalCount(
            campusId: campusId,
            includePast: false,
          );
          eventsTimer.stop();
          logInfo('CampusService._getCampusStats: events count fetched', context: {
            'elapsed_ms': eventsTimer.elapsedMilliseconds,
            'count': count,
          });
          return count;
        } catch (e) {
          return 0;
        }
      }

      Future<int> fetchJobs() async {
        try {
          final jobsTimer = Stopwatch()..start();
          final count = await jobService.getJobsTotalCount(
            campusId: campusId,
            includeExpired: false,
          );
          jobsTimer.stop();
          logInfo('CampusService._getCampusStats: jobs count fetched', context: {
            'elapsed_ms': jobsTimer.elapsedMilliseconds,
            'count': count,
          });
          return count;
        } catch (e) {
          return 0;
        }
      }

      Future<int> fetchMarketplaceItems() async {
        try {
          final marketTimer = Stopwatch()..start();
          final productsResult = await db.listRows(
            databaseId: AppConstants.databaseId,
            tableId: 'products',
            queries: [
              Query.equal('campus_id', campusId),
              Query.equal('status', 'available'),
              Query.limit(1),
              Query.select(['\$id']),
            ],
          );
          marketTimer.stop();
          final count = productsResult.total;
          logInfo('CampusService._getCampusStats: marketplace items counted', context: {
            'elapsed_ms': marketTimer.elapsedMilliseconds,
            'count': count,
          });
          return count;
        } catch (e) {
          return 0;
        }
      }

      Future<int> fetchDepartments() async {
        try {
          final deptsTimer = Stopwatch()..start();
          final departmentsResult = await db.listRows(
            databaseId: AppConstants.databaseId,
            tableId: AppConstants.departmentsCollectionId,
            queries: [
              Query.equal('campus_id', campusId),
              Query.equal('active', true),
              Query.limit(1),
              Query.select(['\$id']),
            ],
          );
          deptsTimer.stop();
          final count = departmentsResult.total;
          logInfo('CampusService._getCampusStats: departments count fetched', context: {
            'elapsed_ms': deptsTimer.elapsedMilliseconds,
            'count': count,
          });
          return count;
        } catch (e) {
          return 0;
        }
      }

      final results = await Future.wait<int>([
        fetchEvents(),
        fetchJobs(),
        fetchMarketplaceItems(),
        fetchDepartments(),
      ]);

      final result = CampusStats(
        studentCount: 0,
        activeEvents: results[0],
        availableJobs: results[1],
        marketplaceItems: results[2],
        departmentsCount: results[3],
      );
      stopwatch.stop();
      logInfo('CampusService._getCampusStats: completed', context: {
        'total_elapsed_ms': stopwatch.elapsedMilliseconds,
      });
      return result;
    } catch (e) {
      stopwatch.stop();
      logError('CampusService._getCampusStats: error', error: e, context: {
        'campus_id': campusId,
        'total_elapsed_ms': stopwatch.elapsedMilliseconds,
      });
      // Return default stats if counting fails
      return const CampusStats();
    }
  }

  Future<WeatherData?> _getWeatherForCampusName(dynamic campusNameRaw) async {
    final stopwatch = Stopwatch()..start();
    logInfo('CampusService._getWeatherForCampusName: start', context: {
      'name_raw_present': campusNameRaw != null,
    });
    try {
      if (campusNameRaw == null) return null;
      final String campusName = campusNameRaw.toString();

      final apiTimer = Stopwatch()..start();
      final weatherModel = await WeatherService.getCampusWeatherByName(campusName);
      apiTimer.stop();
      logInfo('CampusService._getWeatherForCampusName: weather fetched', context: {
        'elapsed_ms': apiTimer.elapsedMilliseconds,
        'campus_name': campusName,
      });
      // Convert to legacy WeatherData compatible with CampusModel
      final wm.WeatherData legacy = weatherModel.toWeatherData();
      final result = WeatherData(
        temperature: legacy.temperature,
        condition: legacy.condition,
        icon: legacy.icon,
        humidity: legacy.humidity,
        windSpeed: legacy.windSpeed,
      );
      stopwatch.stop();
      logInfo('CampusService._getWeatherForCampusName: completed', context: {
        'total_elapsed_ms': stopwatch.elapsedMilliseconds,
      });
      return result;
    } catch (_) {
      stopwatch.stop();
      logWarning('CampusService._getWeatherForCampusName: failed, returning null', context: {
        'total_elapsed_ms': stopwatch.elapsedMilliseconds,
      });
      return null;
    }
  }

  // ======= Caching Helpers =======
  Future<void> _writeCachedCampuses(List<CampusModel> campuses) async {
    final stopwatch = Stopwatch()..start();
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = campuses
          .map((c) => _campusToCacheMap(c))
          .toList(growable: false);
      await prefs.setString(_cacheKeyCampuses, jsonEncode(data));
      await prefs.setString(
        _cacheKeyCampusesUpdatedAt,
        DateTime.now().toIso8601String(),
      );
      stopwatch.stop();
      logInfo('CampusService._writeCachedCampuses: completed', context: {
        'elapsed_ms': stopwatch.elapsedMilliseconds,
        'campus_count': campuses.length,
      });
    } catch (_) {
      // ignore cache write errors
    }
  }

  Future<List<CampusModel>> _readCachedCampuses() async {
    final stopwatch = Stopwatch()..start();
    try {
      final prefs = await SharedPreferences.getInstance();
      final updatedAtStr = prefs.getString(_cacheKeyCampusesUpdatedAt);
      if (updatedAtStr != null) {
        final updatedAt = DateTime.tryParse(updatedAtStr);
        if (updatedAt != null && DateTime.now().difference(updatedAt) > _cacheTtl) {
          // Cache expired
          stopwatch.stop();
          logInfo('CampusService._readCachedCampuses: cache expired', context: {
            'elapsed_ms': stopwatch.elapsedMilliseconds,
          });
          return <CampusModel>[];
        }
      }

      final raw = prefs.getString(_cacheKeyCampuses);
      if (raw == null || raw.isEmpty) return <CampusModel>[];
      final List<dynamic> decoded = jsonDecode(raw);
      final result = decoded
          .whereType<Map<String, dynamic>>()
          .map((m) => CampusModel.fromMap(m))
          .toList(growable: false);
      
      // Sort campuses: campus with ID '5' should always be last, others alphabetically
      result.sort((a, b) {
        // If campus '5' is involved, handle special ordering
        if (a.id == '5') return 1; // Campus '5' goes to the end
        if (b.id == '5') return -1; // Campus '5' goes to the end
        
        // For all other campuses, maintain alphabetical order
        return a.name.compareTo(b.name);
      });
      
      stopwatch.stop();
      logInfo('CampusService._readCachedCampuses: completed', context: {
        'elapsed_ms': stopwatch.elapsedMilliseconds,
        'count': result.length,
      });
      return result;
    } catch (_) {
      return <CampusModel>[];
    }
  }

  Map<String, dynamic> _campusToCacheMap(CampusModel campus) {
    final map = campus.toMap();
    return {
      ...map,
      '\$id': campus.id,
      '\$createdAt': campus.createdAt?.toIso8601String(),
      '\$updatedAt': campus.updatedAt?.toIso8601String(),
    };
  }
}
