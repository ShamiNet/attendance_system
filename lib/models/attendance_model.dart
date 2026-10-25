import 'package:cloud_firestore/cloud_firestore.dart';

class AttendanceRecord {
  final String id;
  final String userId;
  final String userName;
  final String userDivision;
  final String userAffiliation;
  final String zoneId;
  final String zoneName;
  final String dateString;
  final DateTime checkInTime;
  final DateTime? checkOutTime;
  final String checkInType;
  final String? checkOutType;
  final String deviceId;
  final String? bssid;
  final int totalMinutes;
  final int lateMinutes;
  final String shiftStart;
  final String shiftEnd;
  final String status;

  AttendanceRecord({
    required this.id,
    required this.userId,
    this.userName = '',
    this.userDivision = '',
    this.userAffiliation = '',
    required this.zoneId,
    this.zoneName = '',
    required this.dateString,
    required this.checkInTime,
    this.checkOutTime,
    required this.checkInType,
    this.checkOutType,
    required this.deviceId,
    this.bssid,
    this.totalMinutes = 0,
    this.lateMinutes = 0,
    this.shiftStart = '08:00',
    this.shiftEnd = '16:00',
    required this.status,
  });

  bool get isLate => lateMinutes > 0;

  static DateTime _parseDateTime(dynamic val) {
    if (val is Timestamp) return val.toDate();
    if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
    return DateTime.now();
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'userName': userName,
      'userDivision': userDivision,
      'userAffiliation': userAffiliation,
      'zoneId': zoneId,
      'zoneName': zoneName,
      'dateString': dateString,
      'checkIn': {
        'timestamp': checkInTime.toIso8601String(),
        'type': checkInType,
        'bssid': bssid,
      },
      'checkOut': checkOutTime != null
          ? {
              'timestamp': checkOutTime!.toIso8601String(),
              'type': checkOutType,
            }
          : null,
      'deviceId': deviceId,
      'totalMinutes': totalMinutes,
      'lateMinutes': lateMinutes,
      'shiftStart': shiftStart,
      'shiftEnd': shiftEnd,
      'status': status,
    };
  }

  factory AttendanceRecord.fromMap(Map<String, dynamic> map, String docId) {
    final checkInMap = Map<String, dynamic>.from(map['checkIn'] ?? {});
    final checkOutMap = map['checkOut'] != null ? Map<String, dynamic>.from(map['checkOut']) : null;

    return AttendanceRecord(
      id: docId,
      userId: map['userId'] ?? '',
      userName: map['userName'] ?? '',
      userDivision: map['userDivision'] ?? '',
      userAffiliation: map['userAffiliation'] ?? '',
      zoneId: map['zoneId'] ?? '',
      zoneName: map['zoneName'] ?? '',
      dateString: map['dateString'] ?? '',
      checkInTime: _parseDateTime(checkInMap['timestamp']),
      checkOutTime: checkOutMap != null ? _parseDateTime(checkOutMap['timestamp']) : null,
      checkInType: checkInMap['type'] ?? 'MANUAL',
      checkOutType: checkOutMap?['type'],
      deviceId: map['deviceId'] ?? '',
      bssid: checkInMap['bssid'],
      totalMinutes: (map['totalMinutes'] as num?)?.toInt() ?? 0,
      lateMinutes: (map['lateMinutes'] as num?)?.toInt() ?? 0,
      shiftStart: map['shiftStart'] ?? '08:00',
      shiftEnd: map['shiftEnd'] ?? '16:00',
      status: map['status'] ?? 'CHECKED_IN',
    );
  }
}