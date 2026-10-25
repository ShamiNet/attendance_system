String _text(Map<String, dynamic> u, List<String> keys) {
  for (final k in keys) {
    final v = u[k];
    if (v is String && v.trim().isNotEmpty) return v.trim();
  }
  return '';
}

String userName(Map<String, dynamic> u, {String fallback = 'بدون اسم'}) {
  final v = _text(u, ['displayName', 'fullName', 'nickname']);
  return v.isEmpty ? fallback : v;
}

String userJob(Map<String, dynamic> u, {String fallback = 'موظف'}) {
  final v = _text(u, ['job', 'jobTitle', 'specialization']);
  return v.isEmpty ? fallback : v;
}

String userAffiliation(Map<String, dynamic> u, {String fallback = 'العامة'}) {
  final v = _text(u, ['affiliation', 'department']);
  return v.isEmpty ? fallback : v;
}

String userDivision(Map<String, dynamic> u, {String fallback = 'بدون قسم'}) {
  final v = _text(u, ['division', 'section', 'unit']);
  return v.isEmpty ? fallback : v;
}

String userMilitaryNumber(Map<String, dynamic> u) {
  return _text(u, ['militaryNumber', 'employeeNumber', 'badgeNumber']);
}

String? userPhoto(Map<String, dynamic> u) {
  final v = _text(u, ['photoUrl']);
  return v.isEmpty ? null : v;
}

int userTargetWorkDays(Map<String, dynamic> u, {int fallback = 0}) {
  final val = u['targetWorkDays'];
  if (val is num) return val.toInt();
  if (val is String) return int.tryParse(val) ?? fallback;
  return fallback;
}

List<String> userZoneIds(Map<String, dynamic> u) {
  final rawList = u['assignedZoneIds'];
  if (rawList is List && rawList.isNotEmpty) {
    return rawList.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  }
  final single = u['assignedZoneId'] as String?;
  if (single != null && single.trim().isNotEmpty) {
    return [single.trim()];
  }
  return ['ZONE_SCHOOL_MAIN'];
}

String userSubtitle(Map<String, dynamic> u) {
  return [
    userAffiliation(u, fallback: ''),
    userDivision(u, fallback: ''),
    userMilitaryNumber(u),
  ].where((e) => e.isNotEmpty).join(' • ');
}

String normalizeRole(String? role) {
  final r = (role ?? '').toLowerCase().trim();
  if (r == 'owner' || r == 'admin' || r == 'supervisor') return r;
  return 'employee';
}

String roleArabicLabel(String? role) {
  switch (normalizeRole(role)) {
    case 'owner':
      return 'مالك النظام';
    case 'admin':
      return 'مدير عام';
    case 'supervisor':
      return 'مشرف قسم';
    default:
      return 'موظف';
  }
}

bool isPrivilegedRole(String? role) {
  final r = normalizeRole(role);
  return r == 'owner' || r == 'admin' || r == 'supervisor';
}

bool canManageZonesAndRoles(String? role) {
  final r = normalizeRole(role);
  return r == 'owner' || r == 'admin';
}

/// تحويل كائن DateTime إلى نظام 12 ساعة بالعربي (مثال: 08:30 ص أو 04:15 م)
String formatTime12Ar(DateTime dt) {
  int hour = dt.hour;
  final int minute = dt.minute;
  final String period = hour >= 12 ? 'م' : 'ص';
  hour = hour % 12;
  if (hour == 0) hour = 12;
  final String hStr = hour.toString().padLeft(2, '0');
  final String mStr = minute.toString().padLeft(2, '0');
  return '$hStr:$mStr$period';
}

/// تحويل نص وقت الوردية "16:00" إلى نظام 12 ساعة بالعربي "04:00 م"
String formatShift12Ar(String hhmm) {
  final parts = hhmm.trim().split(':');
  if (parts.length < 2) return hhmm;
  int hour = int.tryParse(parts[0]) ?? 8;
  final int minute = int.tryParse(parts[1]) ?? 0;
  final String period = hour >= 12 ? 'م' : 'ص';
  hour = hour % 12;
  if (hour == 0) hour = 12;
  final String hStr = hour.toString().padLeft(2, '0');
  final String mStr = minute.toString().padLeft(2, '0');
  return '$hStr:$mStr$period';
}