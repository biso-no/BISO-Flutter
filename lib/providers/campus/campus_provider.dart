import 'package:biso/core/logging/migration_helper.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/campus_model.dart';
import '../../data/services/campus_service.dart';
import '../auth/auth_provider.dart';
import '../../core/constants/app_constants.dart';

// Filter campus provider - used for filtering content display
final filterCampusStateProvider =
    StateNotifierProvider<FilterCampusNotifier, CampusState>((ref) {
      return FilterCampusNotifier();
    });

// Provider for the current campus (for backward compatibility)
final filterCampusProvider = Provider<CampusModel>((ref) {
  return ref.watch(filterCampusStateProvider).campus;
});

// Provider for checking if campus is initialized
final campusInitializedProvider = Provider<bool>((ref) {
  return ref.watch(filterCampusStateProvider).isInitialized;
});

// DEPRECATED: Use filterCampusProvider instead
// This is kept for backward compatibility during migration
final selectedCampusProvider = Provider<CampusModel>((ref) {
  return ref.watch(filterCampusProvider);
});

// User's profile campus provider - derived from user data
final profileCampusProvider = Provider<CampusModel?>((ref) {
  final authState = ref.watch(authStateProvider);
  final user = authState.user;

  // No static lookup; this provider only exposes user preference if available
  if (user?.campusId != null) {
    // The full CampusModel should be fetched via campusProvider(user.campusId!)
    // Keeping this nullable for compatibility where only ID presence is needed
    return null;
  }
  return null;
});

// All campuses provider - fetches from Appwrite with fallback to static data
final allCampusesProvider = FutureProvider<List<CampusModel>>((ref) async {
  final campusService = CampusService();
  return await campusService.getAllCampuses();
});

// Lightweight campuses for switcher (id, name, address), weather skipped for speed
final switcherCampusesProvider = FutureProvider<List<CampusModel>>((ref) async {
  final campusService = CampusService();
  return await campusService.getSwitcherCampuses(includeWeather: false);
});

// Individual campus provider - fetches specific campus by ID
final campusProvider = FutureProvider.family<CampusModel?, String>((ref, campusId) async {
  final campusService = CampusService();
  return await campusService.getCampusById(campusId);
});

// Synchronous provider for immediate access (with static fallback)
// Removed synchronous fallback provider to avoid showing mock data before load

// Campus state with initialization flag
class CampusState {
  final CampusModel campus;
  final bool isInitialized;

  const CampusState({
    required this.campus,
    required this.isInitialized,
  });

  CampusState copyWith({
    CampusModel? campus,
    bool? isInitialized,
  }) {
    return CampusState(
      campus: campus ?? this.campus,
      isInitialized: isInitialized ?? this.isInitialized,
    );
  }
}

// Filter campus state notifier - manages campus for content filtering
class FilterCampusNotifier extends StateNotifier<CampusState> {
  static const String _filterCampusKey = 'filter_campus_id';
  final CampusService _campusService = CampusService();

  FilterCampusNotifier() : super(const CampusState(
    campus: CampusModel(
      id: '',
      name: '',
      description: '',
      location: '',
      imageUrl: '',
      heroImageUrl: '',
      stats: CampusStats(),
    ),
    isInitialized: false,
  )) {
    _loadFilterCampus();
  }

  Future<void> _loadFilterCampus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final campusId = prefs.getString(_filterCampusKey);

      if (campusId != null) {
        logPrint('🏛️ FilterCampusNotifier: Loading campus with ID: $campusId');
        // Prefer lite fetch to avoid heavy model build
        final campus = await _campusService.getCampusByIdLite(campusId, includeWeather: false)
            ?? await _campusService.getCampusById(campusId);
        if (campus != null) {
          logPrint('✅ FilterCampusNotifier: Updated campus data: ${campus.name}');
          state = state.copyWith(campus: campus);
        }
      } else {
        // No campus set yet: attempt auto-detection once
        logPrint('📍 No campus set. Attempting to auto-detect based on location...');
        await _autoDetectAndSetCampus();
      }
    } catch (e) {
      logPrint('❌ FilterCampusNotifier: Error loading campus: $e');
      // If loading fails, keep current state
    } finally {
      state = state.copyWith(isInitialized: true);
    }
  }

  Future<void> _autoDetectAndSetCampus() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        logPrint('⚠️ Location services are disabled. Falling back to default campus.');
        await _selectDefaultCampusOslo();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        logPrint('🚫 Location permission denied. Falling back to default campus.');
        await _selectDefaultCampusOslo();
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 5),
        ),
      ).timeout(const Duration(seconds: 5));

      final placemarks = await geocoding.placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      String city = placemarks.isNotEmpty
          ? (placemarks.first.locality ?? placemarks.first.administrativeArea ?? '').trim()
          : '';

      city = city.toLowerCase();
      logPrint('📍 Detected city: $city');

      String matchedCampusId = AppConstants.osloId; // default
      if (city.contains('oslo')) {
        matchedCampusId = AppConstants.osloId;
      } else if (city.contains('bergen')) {
        matchedCampusId = AppConstants.bergenId;
      } else if (city.contains('trondheim')) {
        matchedCampusId = AppConstants.trondheimId;
      } else if (city.contains('stavanger')) {
        matchedCampusId = AppConstants.stavangerId;
      }

      await _selectCampusById(matchedCampusId);
    } catch (e) {
      logPrint('❌ Auto-detect campus failed: $e');
      await _selectDefaultCampusOslo();
    }
  }

  Future<void> _selectDefaultCampusOslo() async {
    await _selectCampusById(AppConstants.osloId);
  }

  Future<void> _selectCampusById(String campusId) async {
    try {
      final campus = await _campusService.getCampusByIdLite(campusId, includeWeather: false)
          ?? await _campusService.getCampusById(campusId)
          ?? CampusModel(
            id: campusId,
            name: _displayNameForCampusId(campusId),
            description: '',
            location: '',
            imageUrl: '',
            heroImageUrl: '',
            stats: const CampusStats(),
          );
      await selectFilterCampus(campus);
      logPrint('✅ Auto-selected campus: ${campus.name} (${campus.id})');
    } catch (e) {
      logPrint('❌ Failed to select campus by id $campusId: $e');
    }
  }

  String _displayNameForCampusId(String campusId) {
    switch (campusId) {
      case AppConstants.osloId:
        return 'Oslo';
      case AppConstants.bergenId:
        return 'Bergen';
      case AppConstants.trondheimId:
        return 'Trondheim';
      case AppConstants.stavangerId:
        return 'Stavanger';
      default:
        return campusId;
    }
  }

  Future<void> selectFilterCampus(CampusModel campus) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_filterCampusKey, campus.id);
      // Store name for instant UI header
      await prefs.setString('${_filterCampusKey}_name', campus.name);
      state = state.copyWith(campus: campus);
    } catch (e) {
      // Handle error - maybe show snackbar
      throw Exception('Failed to save filter campus selection');
    }
  }

  Future<void> clearFilterSelection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_filterCampusKey);
      state = state.copyWith(
        campus: const CampusModel(
          id: '',
          name: '',
          description: '',
          location: '',
          imageUrl: '',
          heroImageUrl: '',
          stats: CampusStats(),
        ),
      );
    } catch (e) {
      // Handle error
    }
  }

  // DEPRECATED: Use selectFilterCampus instead
  Future<void> selectCampus(CampusModel campus) async {
    await selectFilterCampus(campus);
  }

  // DEPRECATED: Use clearFilterSelection instead
  Future<void> clearSelection() async {
    await clearFilterSelection();
  }
}

// DEPRECATED class - kept for backward compatibility
class SelectedCampusNotifier extends FilterCampusNotifier {}
