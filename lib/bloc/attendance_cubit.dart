import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import '../models/attendance_model.dart';
import '../models/zone_model.dart';
import '../services/attendance_service.dart';
import '../services/geofence_manager.dart';
import '../services/work_timer_controller.dart';
import '../core/services/network_service.dart';
import '../core/services/user_fields.dart';

abstract class AttendanceState {}

class AttendanceLoading extends AttendanceState {}

class AttendanceError extends AttendanceState {
  final String message;
  AttendanceError(this.message);
}

class AttendanceLoaded extends AttendanceState {
  final AttendanceRecord? record;
  final bool isInsideZone;
  final double? currentDistanceMeters;
  final bool isWifiConnected;
  final int pendingOfflineCount;
  final int attendedDaysCount;
  final int targetWorkDays;
  final Map<String, dynamic> userProfile;
  final List<WorkZone> assignedZones;
  final WorkZone selectedZone;

  AttendanceLoaded({
    required this.record,
    required this.isInsideZone,
    this.currentDistanceMeters,
    required this.isWifiConnected,
    this.pendingOfflineCount = 0,
    this.attendedDaysCount = 0,
    this.targetWorkDays = 0,
    required this.userProfile,
    required this.assignedZones,
    required this.selectedZone,
  });
}

class AttendanceCubit extends Cubit<AttendanceState> {
  final AttendanceService _attendanceService = AttendanceService();
  final GeofenceManager _geofenceManager = GeofenceManager();
  final WorkTimerController timerController = WorkTimerController();

  StreamSubscription? _attendanceSub;
  AttendanceRecord? _latestRecord;
  Map<String, dynamic> _userData = {};
  List<WorkZone> _assignedZones = [];
  WorkZone? _selectedZone;
  String _currentUserId = '';

  AttendanceCubit() : super(AttendanceLoading());

  void init(String userId) async {
    _currentUserId = userId;
    emit(AttendanceLoading());
    try {
      await _attendanceService.syncOfflineRecords();

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      if (!userDoc.exists || userDoc.data() == null) {
        emit(AttendanceError('بيانات المستخدم غير موجودة'));
        return;
      }
      _userData = userDoc.data()!;
      final zoneIds = userZoneIds(_userData);

      _assignedZones = await _attendanceService.getAssignedZones(zoneIds);
      _selectedZone = _assignedZones.first;

      await _geofenceManager.startMonitoringZones(
        userId: userId,
        zones: _assignedZones,
      );

      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      _attendanceSub?.cancel();
      _attendanceSub = FirebaseFirestore.instance
          .collection('attendance_records')
          .doc('${todayStr}_$userId')
          .snapshots()
          .listen((snapshot) async {
        if (snapshot.exists && snapshot.data() != null) {
          _latestRecord = AttendanceRecord.fromMap(snapshot.data()!, snapshot.id);
          if (_latestRecord!.status == 'CHECKED_IN') {
            timerController.start(_latestRecord!.checkInTime);
          } else {
            timerController.stop();
          }
        } else {
          _latestRecord = null;
          timerController.stop();
        }
        await refreshTelemetry(autoPickNearest: true);
      }, onError: (err) {
        emit(AttendanceError(err.toString()));
      });
    } catch (e) {
      emit(AttendanceError(e.toString()));
    }
  }

  Future<void> selectZone(WorkZone zone) async {
    _selectedZone = zone;
    await refreshTelemetry(autoPickNearest: false);
  }

  Future<void> refreshTelemetry({bool autoPickNearest = false}) async {
    if (_assignedZones.isEmpty) return;
    _selectedZone ??= _assignedZones.first;

    double? distance;
    bool inside = false;
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 6),
          ),
        );

        if (autoPickNearest && _assignedZones.length > 1) {
          WorkZone? nearest;
          double minDistance = double.infinity;
          for (final z in _assignedZones) {
            if (z.latitude == 0.0 && z.longitude == 0.0) continue;
            final d = Geolocator.distanceBetween(pos.latitude, pos.longitude, z.latitude, z.longitude);
            if (d < minDistance) {
              minDistance = d;
              nearest = z;
            }
          }
          if (nearest != null) _selectedZone = nearest;
        }

        final z = _selectedZone!;
        if (z.latitude != 0.0 || z.longitude != 0.0) {
          distance = Geolocator.distanceBetween(pos.latitude, pos.longitude, z.latitude, z.longitude);
          inside = distance <= z.radiusMeters;
        } else {
          inside = true;
        }
      }
    } catch (_) {}

    final z = _selectedZone!;
    final currentBssid = await NetworkService.getCurrentBSSID();
    final wifiValid = z.allowedBssids.isEmpty || NetworkService.isAuthorizedWifi(currentBssid, z.allowedBssids);
    final pendingCount = await _attendanceService.getPendingOfflineCount();

    // حساب عدد أيام الحضور الفعلي للموظف
    int attendedDays = 0;
    try {
      final attSnap = await FirebaseFirestore.instance
          .collection('attendance_records')
          .where('userId', isEqualTo: _currentUserId)
          .get();
      attendedDays = attSnap.docs.length;
    } catch (_) {}

    final userTarget = userTargetWorkDays(_userData);
    final effectiveTargetDays = userTarget > 0 ? userTarget : z.durationDays;

    if (!isClosed) {
      emit(AttendanceLoaded(
        record: _latestRecord,
        isInsideZone: inside,
        currentDistanceMeters: distance,
        isWifiConnected: wifiValid,
        pendingOfflineCount: pendingCount,
        attendedDaysCount: attendedDays,
        targetWorkDays: effectiveTargetDays,
        userProfile: _userData,
        assignedZones: _assignedZones,
        selectedZone: z,
      ));
    }
  }

  Future<int> syncOfflineNow() async {
    final count = await _attendanceService.syncOfflineRecords();
    await refreshTelemetry();
    return count;
  }

  Future<void> triggerManualCheckIn(String userId) async {
    if (_selectedZone == null) return;
    try {
      await _attendanceService.checkIn(
        userId: userId,
        zone: _selectedZone!,
        isAutomatic: false,
      );
      await refreshTelemetry();
    } catch (e) {
      emit(AttendanceError(e.toString().replaceAll('Exception: ', '')));
      await refreshTelemetry();
    }
  }

  Future<void> triggerManualCheckOut(String userId) async {
    try {
      await _attendanceService.checkOut(userId: userId, isAutomatic: false);
      await refreshTelemetry();
    } catch (e) {
      emit(AttendanceError(e.toString().replaceAll('Exception: ', '')));
      await refreshTelemetry();
    }
  }

  @override
  Future<void> close() {
    _attendanceSub?.cancel();
    timerController.dispose();
    return super.close();
  }
}