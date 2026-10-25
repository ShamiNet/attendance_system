class WorkZone {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final List<String> allowedBssids;
  final String shiftStart; // يخزن بصيغة "08:00" ويعرض "08:00 ص"
  final String shiftEnd;   // يخزن بصيغة "16:00" ويعرض "04:00 م"
  final int graceMinutes;
  final List<int> workDays;
  final int durationDays; // عدد أيام الدوام المقررة (مثال: 10 أيام، 0 = مستمر)

  const WorkZone({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 100.0,
    this.allowedBssids = const [],
    this.shiftStart = '08:00',
    this.shiftEnd = '16:00',
    this.graceMinutes = 15,
    this.workDays = const [6, 7, 1, 2, 3, 4],
    this.durationDays = 10,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'coordinates': {
        'latitude': latitude,
        'longitude': longitude,
      },
      'radiusMeters': radiusMeters,
      'allowedBSSIDs': allowedBssids,
      'shiftStart': shiftStart,
      'shiftEnd': shiftEnd,
      'graceMinutes': graceMinutes,
      'workDays': workDays,
      'durationDays': durationDays,
    };
  }

  factory WorkZone.fromMap(Map<String, dynamic> map, String docId) {
    final coords = map['coordinates'] as Map<String, dynamic>?;
    final rawBssids = map['allowedBSSIDs'] as List<dynamic>? ?? [];
    final rawDays = map['workDays'] as List<dynamic>?;

    return WorkZone(
      id: docId,
      name: (map['name'] as String?)?.trim().isNotEmpty == true
          ? map['name'] as String
          : 'موقع عمل ($docId)',
      latitude: (coords?['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (coords?['longitude'] as num?)?.toDouble() ?? 0.0,
      radiusMeters: (map['radiusMeters'] as num?)?.toDouble() ?? 100.0,
      allowedBssids: rawBssids.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList(),
      shiftStart: (map['shiftStart'] as String?) ?? '08:00',
      shiftEnd: (map['shiftEnd'] as String?) ?? '16:00',
      graceMinutes: (map['graceMinutes'] as num?)?.toInt() ?? 15,
      workDays: rawDays != null
          ? rawDays.map((e) => (e as num).toInt()).toList()
          : const [6, 7, 1, 2, 3, 4],
      durationDays: (map['durationDays'] as num?)?.toInt() ?? 0,
    );
  }

  int calculateLateMinutes(DateTime checkInTime) {
    if (!workDays.contains(checkInTime.weekday)) return 0;
    final parts = shiftStart.split(':');
    if (parts.length < 2) return 0;
    final hour = int.tryParse(parts[0]) ?? 8;
    final minute = int.tryParse(parts[1]) ?? 0;

    final scheduledStart = DateTime(
      checkInTime.year,
      checkInTime.month,
      checkInTime.day,
      hour,
      minute,
    );
    final latestAllowed = scheduledStart.add(Duration(minutes: graceMinutes));

    if (checkInTime.isAfter(latestAllowed)) {
      return checkInTime.difference(scheduledStart).inMinutes;
    }
    return 0;
  }
}