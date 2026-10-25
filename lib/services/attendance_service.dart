import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import '../models/zone_model.dart';
import '../core/services/device_service.dart';
import '../core/services/network_service.dart';
import '../core/services/user_fields.dart';
import '../core/database/offline_sync_database.dart';

class AttendanceService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String getTodayString() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  Future<int> getPendingOfflineCount() async {
    final records = await OfflineSyncDatabase.getUnsyncedRecords();
    return records.length;
  }

  Future<bool> isAlreadyCheckedIn(String userId) async {
    final today = getTodayString();
    final docId = '${today}_$userId';
    try {
      final doc = await _firestore.collection('attendance_records').doc(docId).get();
      if (doc.exists) {
        return doc.data()?['status'] == 'CHECKED_IN';
      }
    } catch (_) {}
    return false;
  }

  /// جلب كافة مواقع العمل المسندة للموظف
  Future<List<WorkZone>> getAssignedZones(List<String> zoneIds) async {
    final zones = <WorkZone>[];
    for (final id in zoneIds) {
      try {
        final doc = await _firestore.collection('zones').doc(id).get();
        if (doc.exists && doc.data() != null) {
          zones.add(WorkZone.fromMap(doc.data()!, doc.id));
        }
      } catch (_) {}
    }
    if (zones.isEmpty) {
      final fallbackDoc = await _firestore.collection('zones').doc('ZONE_SCHOOL_MAIN').get();
      if (fallbackDoc.exists && fallbackDoc.data() != null) {
        zones.add(WorkZone.fromMap(fallbackDoc.data()!, fallbackDoc.id));
      } else {
        zones.add(const WorkZone(
          id: 'ZONE_SCHOOL_MAIN',
          name: 'المقر الرئيسي',
          latitude: 0.0,
          longitude: 0.0,
        ));
      }
    }
    return zones;
  }

  Future<void> checkIn({
    required String userId,
    required WorkZone zone,
    required bool isAutomatic,
  }) async {
    final now = DateTime.now();
    final today = getTodayString();
    final currentDeviceId = await DeviceService.getUniqueDeviceId();

    String empName = 'موظف';
    String empJob = '';
    String empDivision = '';
    String empAffiliation = '';

    final userRef = _firestore.collection('users').doc(userId);
    final userDoc = await userRef.get();
    if (userDoc.exists && userDoc.data() != null) {
      final userData = userDoc.data()!;
      if (userData['isBlocked'] == true) {
        throw Exception('تم إيقاف حسابك من قِبل الإدارة. راجع المسؤول.');
      }

      empName = userName(userData, fallback: 'موظف');
      empJob = userJob(userData, fallback: '');
      empDivision = userDivision(userData, fallback: '');
      empAffiliation = userAffiliation(userData, fallback: '');

      final registeredDevice = userData['deviceId'] as String?;
      if (registeredDevice != null &&
          registeredDevice.isNotEmpty &&
          registeredDevice != currentDeviceId) {
        throw Exception('هذا الحساب مقترن بجهاز فيزيائي آخر!');
      }

      if (registeredDevice == null || registeredDevice.isEmpty) {
        await userRef.update({'deviceId': currentDeviceId});
      }
    }

    if (!zone.workDays.contains(now.weekday)) {
      throw Exception('اليوم ليس من أيام الدوام المجدولة لموقع (${zone.name}).');
    }

    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('خدمة الموقع (GPS) متوقفة. يرجى تفعيلها ثم المحاولة مجدداً.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw Exception('تم رفض صلاحية الموقع. يرجى السماح بها لتسجيل الحضور.');
    }
    if (permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      throw Exception('صلاحية الموقع مرفوضة نهائياً. فعّلها من إعدادات التطبيق.');
    }

    final currentPos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );

    if (currentPos.isMocked) {
      throw Exception('تم رصد محاولة تزييف موقع جغرافي (Mock Location). تم رفض الطلب!');
    }

    if (zone.latitude != 0.0 || zone.longitude != 0.0) {
      final double distance = Geolocator.distanceBetween(
        currentPos.latitude,
        currentPos.longitude,
        zone.latitude,
        zone.longitude,
      );

      if (distance > zone.radiusMeters) {
        throw Exception('أنت خارج نطاق (${zone.name}) بمقدار ${distance.toInt()} متر.');
      }
    }

    final currentBSSID = await NetworkService.getCurrentBSSID();
    if (zone.allowedBssids.isNotEmpty &&
        !NetworkService.isAuthorizedWifi(currentBSSID, zone.allowedBssids)) {
      throw Exception('أنت غير متصل بشبكة الواي فاي المعتمدة لموقع (${zone.name}).');
    }

    final lateMins = zone.calculateLateMinutes(now);
    final recordId = '${today}_$userId';
    final payload = {
      'userId': userId,
      'userName': empName,
      'userJob': empJob,
      'userDivision': empDivision,
      'userAffiliation': empAffiliation,
      'zoneId': zone.id,
      'zoneName': zone.name,
      'dateString': today,
      'shiftStart': zone.shiftStart,
      'shiftEnd': zone.shiftEnd,
      'lateMinutes': lateMins,
      'checkIn': {
        'timestamp': now.toIso8601String(),
        'type': isAutomatic ? 'AUTO' : 'MANUAL',
        'bssid': currentBSSID,
        'lat': currentPos.latitude,
        'lng': currentPos.longitude,
      },
      'deviceId': currentDeviceId,
      'status': 'CHECKED_IN',
      'totalMinutes': 0,
    };

    try {
      await _firestore
          .collection('attendance_records')
          .doc(recordId)
          .set(payload, SetOptions(merge: true));
    } catch (_) {
      await OfflineSyncDatabase.queueAttendance({
        'userId': userId,
        'zoneId': zone.id,
        'actionType': 'CHECK_IN',
        'timestamp': now.toIso8601String(),
        'method': isAutomatic ? 'AUTO' : 'MANUAL',
        'bssid': currentBSSID,
        'deviceId': currentDeviceId,
        'isSynced': 0,
      });
    }
  }

  Future<void> checkOut({
    required String userId,
    required bool isAutomatic,
  }) async {
    final now = DateTime.now();
    final today = getTodayString();
    final recordId = '${today}_$userId';
    final docRef = _firestore.collection('attendance_records').doc(recordId);

    try {
      final doc = await docRef.get();
      if (!doc.exists) return;

      final data = doc.data()!;
      if (data['status'] == 'COMPLETED') return;

      final checkInTime = DateTime.parse(data['checkIn']['timestamp']);
      final diffMinutes = now.difference(checkInTime).inMinutes;

      await docRef.update({
        'checkOut': {
          'timestamp': now.toIso8601String(),
          'type': isAutomatic ? 'AUTO' : 'MANUAL',
        },
        'totalMinutes': diffMinutes < 0 ? 0 : diffMinutes,
        'status': 'COMPLETED',
      });
    } catch (_) {
      await OfflineSyncDatabase.queueAttendance({
        'userId': userId,
        'zoneId': '',
        'actionType': 'CHECK_OUT',
        'timestamp': now.toIso8601String(),
        'method': isAutomatic ? 'AUTO' : 'MANUAL',
        'deviceId': await DeviceService.getUniqueDeviceId(),
        'isSynced': 0,
      });
    }
  }

  Future<int> syncOfflineRecords() async {
    final unsynced = await OfflineSyncDatabase.getUnsyncedRecords();
    int syncedCount = 0;

    for (var row in unsynced) {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.parse(row['timestamp']));
      final recordId = '${today}_${row['userId']}';

      try {
        if (row['actionType'] == 'CHECK_IN') {
          await _firestore.collection('attendance_records').doc(recordId).set({
            'userId': row['userId'],
            'zoneId': row['zoneId'],
            'dateString': today,
            'checkIn': {
              'timestamp': row['timestamp'],
              'type': row['method'],
              'bssid': row['bssid'],
            },
            'deviceId': row['deviceId'],
            'status': 'CHECKED_IN',
            'totalMinutes': 0,
          }, SetOptions(merge: true));
        } else {
          final doc = await _firestore.collection('attendance_records').doc(recordId).get();
          int diff = 0;
          if (doc.exists && doc.data()?['checkIn'] != null) {
            final checkInTime = DateTime.parse(doc.data()!['checkIn']['timestamp']);
            diff = DateTime.parse(row['timestamp']).difference(checkInTime).inMinutes;
          }
          await _firestore.collection('attendance_records').doc(recordId).update({
            'checkOut': {
              'timestamp': row['timestamp'],
              'type': row['method'],
            },
            'totalMinutes': diff < 0 ? 0 : diff,
            'status': 'COMPLETED',
          });
        }
        await OfflineSyncDatabase.markAsSynced(row['id']);
        syncedCount++;
      } catch (_) {
        break;
      }
    }
    return syncedCount;
  }
}