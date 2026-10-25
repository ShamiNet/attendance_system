import 'dart:async';
import 'package:geofence_service/geofence_service.dart';
import '../models/zone_model.dart';
import 'attendance_service.dart';

class GeofenceManager {
  static final GeofenceManager _instance = GeofenceManager._internal();
  factory GeofenceManager() => _instance;
  GeofenceManager._internal();

  final _geofenceService = GeofenceService.instance.setup(
    interval: 5000,
    accuracy: 100,
    loiteringDelayMs: 60000,
    statusChangeDelayMs: 10000,
    useActivityRecognition: false,
    allowMockLocations: false,
    printDevLog: false,
    geofenceRadiusSortType: GeofenceRadiusSortType.DESC,
  );

  final AttendanceService _attendanceService = AttendanceService();

  bool _isListenerAttached = false;
  bool _isProcessing = false;

  String? _activeUserId;
  final Map<String, WorkZone> _monitoredZones = {};

  Future<void> startMonitoringZones({
    required String userId,
    required List<WorkZone> zones,
  }) async {
    _activeUserId = userId;
    _monitoredZones.clear();

    final geofenceList = <Geofence>[];
    for (final z in zones) {
      if (z.latitude == 0.0 && z.longitude == 0.0) continue;
      _monitoredZones[z.id] = z;
      geofenceList.add(
        Geofence(
          id: z.id,
          latitude: z.latitude,
          longitude: z.longitude,
          radius: [
            GeofenceRadius(id: 'radius_${z.id}', length: z.radiusMeters),
          ],
        ),
      );
    }

    if (geofenceList.isEmpty) return;

    if (!_isListenerAttached) {
      _geofenceService.addGeofenceStatusChangeListener(_onGeofenceStatusChange);
      _isListenerAttached = true;
    }

    await _geofenceService.start(geofenceList).catchError((_) {});
  }

  Future<void> _onGeofenceStatusChange(
    Geofence geofence,
    GeofenceRadius geofenceRadius,
    GeofenceStatus geofenceStatus,
    Location location,
  ) async {
    if (_isProcessing || _activeUserId == null) return;
    _isProcessing = true;

    try {
      final matchedZone = _monitoredZones[geofence.id];
      if (matchedZone == null) return;

      if (geofenceStatus == GeofenceStatus.ENTER || geofenceStatus == GeofenceStatus.DWELL) {
        final active = await _attendanceService.isAlreadyCheckedIn(_activeUserId!);
        if (!active) {
          await _attendanceService.checkIn(
            userId: _activeUserId!,
            zone: matchedZone,
            isAutomatic: true,
          );
        }
      } else if (geofenceStatus == GeofenceStatus.EXIT) {
        await _attendanceService.checkOut(
          userId: _activeUserId!,
          isAutomatic: true,
        );
      }
    } catch (_) {
    } finally {
      _isProcessing = false;
    }
  }

  void stopMonitoring() {
    _geofenceService.stop();
  }
}