import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../models/zone_model.dart';
import '../services/auth_service.dart';
import '../core/services/user_fields.dart';
import '../core/services/network_service.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // متحكمات إعدادات موقع العمل والدوام
  final TextEditingController _zoneNameController = TextEditingController();
  final TextEditingController _latController = TextEditingController();
  final TextEditingController _lngController = TextEditingController();
  final TextEditingController _radiusController = TextEditingController();
  final TextEditingController _bssidController = TextEditingController();
  final TextEditingController _graceController = TextEditingController(
    text: '15',
  );
  final TextEditingController _durationDaysController = TextEditingController(
    text: '10',
  );
  String _shiftStart = '08:00';
  String _shiftEnd = '16:00';
  List<int> _workDays = [6, 7, 1, 2, 3, 4];

  List<WorkZone> _allZones = [];
  String _selectedZoneId = 'ZONE_SCHOOL_MAIN';
  bool _isLoadingZone = true;

  // متحكمات البحث والفلترة والتحديد المتعدد للموظفين
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _filterAffiliation = 'الكل';
  String _filterDivision = 'الكل';
  String _filterRole = 'الكل';
  final Set<String> _selectedUserIds = {};

  // فلترة سجل الحضور
  DateTime _selectedDate = DateTime.now();
  String _attendanceZoneFilter = 'الكل';
  String _attendanceStatusFilter = 'الكل';

  // صلاحيات المستخدم الحالي
  String _currentUserRole = 'owner';
  String _currentUserDivision = '';

  final MapController _mapController = MapController();
  static const LatLng _defaultCenter = LatLng(35.9304, 36.6339);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initAdminContext();
  }

  Future<void> _initAdminContext() async {
    final uid = AuthService().currentUser?.uid;
    if (uid != null) {
      try {
        final uDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        if (uDoc.exists && uDoc.data() != null) {
          _currentUserRole = normalizeRole(uDoc.data()!['role'] as String?);
          _currentUserDivision = userDivision(uDoc.data()!, fallback: '');
        }
      } catch (_) {}
    }
    await _loadAllZones();
  }

  Future<void> _loadAllZones({String? selectId}) async {
    try {
      final snap = await FirebaseFirestore.instance.collection('zones').get();
      final list = snap.docs
          .map((d) => WorkZone.fromMap(d.data(), d.id))
          .toList();
      if (list.isEmpty) {
        const defaultZone = WorkZone(
          id: 'ZONE_SCHOOL_MAIN',
          name: 'المقر الرئيسي',
          latitude: 35.9304,
          longitude: 36.6339,
          radiusMeters: 150,
          durationDays: 10,
        );
        await FirebaseFirestore.instance
            .collection('zones')
            .doc(defaultZone.id)
            .set(defaultZone.toMap());
        list.add(defaultZone);
      }
      _allZones = list;
      final targetId = selectId ?? _selectedZoneId;
      final matched = _allZones.where((z) => z.id == targetId).toList();
      _populateZoneForm(matched.isNotEmpty ? matched.first : _allZones.first);
    } catch (_) {}
    if (mounted) setState(() => _isLoadingZone = false);
  }

  void _populateZoneForm(WorkZone z) {
    _selectedZoneId = z.id;
    _zoneNameController.text = z.name;
    _latController.text = z.latitude.toString();
    _lngController.text = z.longitude.toString();
    _radiusController.text = z.radiusMeters.toString();
    _bssidController.text = z.allowedBssids.join(', ');
    _graceController.text = z.graceMinutes.toString();
    _durationDaysController.text = z.durationDays.toString();
    _shiftStart = z.shiftStart;
    _shiftEnd = z.shiftEnd;
    _workDays = List<int>.from(z.workDays);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabController.dispose();
    _zoneNameController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _radiusController.dispose();
    _bssidController.dispose();
    _graceController.dispose();
    _durationDaysController.dispose();
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  // ==================== منتقي وقت بنظام 12 ساعة بالعربي ====================
  Future<void> _pickShiftTime({required bool isStart}) async {
    final currentStr = isStart ? _shiftStart : _shiftEnd;
    final parts = currentStr.split(':');
    final initialHour = int.tryParse(parts.first) ?? (isStart ? 8 : 16);
    final initialMinute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initialHour, minute: initialMinute),
      helpText: isStart
          ? 'تحديد وقت بداية الدوام (12 ساعة)'
          : 'تحديد وقت نهاية الدوام (12 ساعة)',
      cancelText: 'إلغاء',
      confirmText: 'اعتماد الوقت',
      hourLabelText: 'الساعة',
      minuteLabelText: 'الدقيقة',
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
            child: Theme(
              data: ThemeData.dark().copyWith(
                colorScheme: const ColorScheme.dark(
                  primary: Color(0xFF38BDF8),
                  surface: Color(0xFF1E293B),
                ),
              ),
              child: child!,
            ),
          ),
        );
      },
    );

    if (picked != null && mounted) {
      final formatted24 =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      setState(() {
        if (isStart) {
          _shiftStart = formatted24;
        } else {
          _shiftEnd = formatted24;
        }
      });
    }
  }

  // ==================== إنشاء حساب جديد مع تحديد الدوام بالأيام ====================
  Future<void> _showAddAccountDialog() async {
    final nameC = TextEditingController();
    final jobC = TextEditingController();
    final affiliationC = TextEditingController(text: 'الإدارة العامة');
    final divisionC = TextEditingController(
      text: _currentUserDivision.isNotEmpty
          ? _currentUserDivision
          : 'القسم الرئيسي',
    );
    final militaryC = TextEditingController();
    final targetDaysC = TextEditingController(text: '10');
    final emailC = TextEditingController();
    final passC = TextEditingController();
    String selectedRole = 'employee';
    final selectedZones = <String>{
      _allZones.isNotEmpty ? _allZones.first.id : 'ZONE_SCHOOL_MAIN',
    };
    bool saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: const Text(
              'إضافة حساب كادر جديد',
              style: TextStyle(color: Colors.white, fontSize: 17),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _dialogField(nameC, 'الاسم الكامل'),
                    _dialogField(jobC, 'المسمى الوظيفي / الاختصاص'),
                    Row(
                      children: [
                        Expanded(child: _dialogField(affiliationC, 'التبعية')),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _dialogField(divisionC, 'القسم / الفرقة'),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _dialogField(
                            militaryC,
                            'الرقم الوظيفي / العسكري',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _dialogField(
                            targetDaysC,
                            'أيام الدوام (مثال: 10)',
                            keyboard: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 6,
                      children: [5, 10, 15, 20, 30, 0].map((d) {
                        final isSel =
                            (int.tryParse(targetDaysC.text) ?? -1) == d;
                        return ChoiceChip(
                          label: Text(
                            d == 0 ? 'مفتوح' : '$d أيام',
                            style: const TextStyle(fontSize: 10),
                          ),
                          selected: isSel,
                          selectedColor: const Color(0xFF0284C7),
                          backgroundColor: const Color(0xFF0F172A),
                          labelStyle: TextStyle(
                            color: isSel ? Colors.white : Colors.white70,
                          ),
                          onSelected: (_) =>
                              setLocal(() => targetDaysC.text = d.toString()),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    _dialogField(
                      emailC,
                      'البريد الإلكتروني',
                      keyboard: TextInputType.emailAddress,
                    ),
                    _dialogField(
                      passC,
                      'كلمة المرور (6 أحرف فأكثر)',
                      obscure: true,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'مستوى الصلاحية:',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: selectedRole,
                      dropdownColor: const Color(0xFF0F172A),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'employee',
                          child: Text('موظف (تسجيل حضور فقط)'),
                        ),
                        DropdownMenuItem(
                          value: 'supervisor',
                          child: Text('مشرف قسم (متابعة قسمه)'),
                        ),
                        DropdownMenuItem(
                          value: 'admin',
                          child: Text('مدير عام (إدارة شاملة)'),
                        ),
                        DropdownMenuItem(
                          value: 'owner',
                          child: Text('مالك النظام (صلاحية مطلقة)'),
                        ),
                      ],
                      onChanged: saving
                          ? null
                          : (v) =>
                                setLocal(() => selectedRole = v ?? 'employee'),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'مواقع الدوام المسموحة (يمكن تحديد أكثر من موقع):',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _allZones.map((z) {
                        final isSelected = selectedZones.contains(z.id);
                        return FilterChip(
                          label: Text(
                            z.name,
                            style: const TextStyle(fontSize: 11),
                          ),
                          selected: isSelected,
                          selectedColor: const Color(0xFF0284C7),
                          checkmarkColor: Colors.white,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : Colors.white70,
                          ),
                          backgroundColor: const Color(0xFF0F172A),
                          onSelected: saving
                              ? null
                              : (val) {
                                  setLocal(() {
                                    if (val) {
                                      selectedZones.add(z.id);
                                    } else if (selectedZones.length > 1) {
                                      selectedZones.remove(z.id);
                                    }
                                  });
                                },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                ),
                onPressed: saving
                    ? null
                    : () async {
                        if (nameC.text.trim().isEmpty ||
                            emailC.text.trim().isEmpty ||
                            passC.text.length < 6) {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'أكمل الحقول الأساسية وتأكد من طول كلمة المرور',
                              ),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                          return;
                        }
                        setLocal(() => saving = true);
                        try {
                          await AuthService().createAccountByAdmin(
                            fullName: nameC.text,
                            email: emailC.text,
                            password: passC.text,
                            jobTitle: jobC.text,
                            affiliation: affiliationC.text,
                            division: divisionC.text,
                            militaryNumber: militaryC.text,
                            role: selectedRole,
                            targetWorkDays:
                                int.tryParse(targetDaysC.text) ?? 10,
                            assignedZoneIds: selectedZones.toList(),
                          );
                          if (dialogContext.mounted)
                            Navigator.pop(dialogContext);
                          if (mounted) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(
                                content: Text('تم إنشاء الحساب بنجاح'),
                                backgroundColor: Color(0xFF10B981),
                              ),
                            );
                          }
                        } catch (e) {
                          setLocal(() => saving = false);
                          if (mounted) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                content: Text(AuthService.friendlyError(e)),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                          }
                        }
                      },
                child: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'إنشاء الحساب',
                        style: TextStyle(color: Colors.white),
                      ),
              ),
            ],
          ),
        ),
      ),
    );

    nameC.dispose();
    jobC.dispose();
    affiliationC.dispose();
    divisionC.dispose();
    militaryC.dispose();
    targetDaysC.dispose();
    emailC.dispose();
    passC.dispose();
  }

  // ==================== العمليات الجماعية (مواقع الدوام + تحديد عدد أيام الدوام + التبعية) ====================
  Future<void> _showBulkAssignZonesDialog() async {
    if (_selectedUserIds.isEmpty) return;
    final chosenZones = <String>{
      _allZones.isNotEmpty ? _allZones.first.id : 'ZONE_SCHOOL_MAIN',
    };

    await showDialog<void>(
      context: context,
      builder: (dCtx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: Text(
              'تعيين مواقع الدوام لـ (${_selectedUserIds.length}) موظف',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            content: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _allZones.map((z) {
                final sel = chosenZones.contains(z.id);
                return FilterChip(
                  label: Text(z.name),
                  selected: sel,
                  selectedColor: const Color(0xFF0284C7),
                  checkmarkColor: Colors.white,
                  labelStyle: TextStyle(
                    color: sel ? Colors.white : Colors.white70,
                  ),
                  backgroundColor: const Color(0xFF0F172A),
                  onSelected: (v) {
                    setLocal(() {
                      if (v) {
                        chosenZones.add(z.id);
                      } else if (chosenZones.length > 1) {
                        chosenZones.remove(z.id);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dCtx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                ),
                onPressed: () async {
                  final batch = FirebaseFirestore.instance.batch();
                  final list = chosenZones.toList();
                  for (final uid in _selectedUserIds) {
                    final ref = FirebaseFirestore.instance
                        .collection('users')
                        .doc(uid);
                    batch.update(ref, {
                      'assignedZoneIds': list,
                      'assignedZoneId': list.first,
                    });
                  }
                  await batch.commit();
                  if (dCtx.mounted) Navigator.pop(dCtx);
                  if (mounted) {
                    setState(() => _selectedUserIds.clear());
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'تم تحديث مواقع الدوام للموظفين المحددين',
                        ),
                        backgroundColor: Color(0xFF10B981),
                      ),
                    );
                  }
                },
                child: const Text(
                  'حفظ التعيين',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showBulkWorkDaysDialog() async {
    if (_selectedUserIds.isEmpty) return;
    final daysC = TextEditingController(text: '10');

    await showDialog<void>(
      context: context,
      builder: (dCtx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: Text(
              'تحديد أيام الدوام لـ (${_selectedUserIds.length}) موظف',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _dialogField(
                  daysC,
                  'عدد أيام الدوام المطلوبة (0 = دوام مفتوح)',
                  keyboard: TextInputType.number,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [5, 10, 15, 20, 30, 0].map((d) {
                    final isSel = (int.tryParse(daysC.text) ?? -1) == d;
                    return ChoiceChip(
                      label: Text(
                        d == 0 ? 'مفتوح' : '$d أيام',
                        style: const TextStyle(fontSize: 11),
                      ),
                      selected: isSel,
                      selectedColor: const Color(0xFF0284C7),
                      backgroundColor: const Color(0xFF0F172A),
                      labelStyle: TextStyle(
                        color: isSel ? Colors.white : Colors.white70,
                      ),
                      onSelected: (_) =>
                          setLocal(() => daysC.text = d.toString()),
                    );
                  }).toList(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dCtx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                ),
                onPressed: () async {
                  final targetDays = int.tryParse(daysC.text.trim()) ?? 10;
                  final batch = FirebaseFirestore.instance.batch();
                  for (final uid in _selectedUserIds) {
                    final ref = FirebaseFirestore.instance
                        .collection('users')
                        .doc(uid);
                    batch.update(ref, {'targetWorkDays': targetDays});
                  }
                  await batch.commit();
                  if (dCtx.mounted) Navigator.pop(dCtx);
                  if (mounted) {
                    setState(() => _selectedUserIds.clear());
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(
                        content: Text(
                          targetDays > 0
                              ? 'تم تحديد الدوام بـ $targetDays أيام للموظفين المحددين'
                              : 'تم جعل الدوام مفتوحاً للموظفين المحددين',
                        ),
                        backgroundColor: const Color(0xFF10B981),
                      ),
                    );
                  }
                },
                child: const Text(
                  'تطبيق',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    daysC.dispose();
  }

  Future<void> _showBulkDivisionDialog() async {
    if (_selectedUserIds.isEmpty) return;
    final affC = TextEditingController();
    final divC = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dCtx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: Text(
            'نقل التبعية والقسم لـ (${_selectedUserIds.length}) موظف',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogField(affC, 'التبعية الجديدة (اتركه فارغاً لعدم التغيير)'),
              _dialogField(
                divC,
                'القسم / الفرقة الجديدة (اتركه فارغاً لعدم التغيير)',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
              ),
              onPressed: () async {
                final updates = <String, dynamic>{};
                if (affC.text.trim().isNotEmpty)
                  updates['affiliation'] = affC.text.trim();
                if (divC.text.trim().isNotEmpty)
                  updates['division'] = divC.text.trim();
                if (updates.isNotEmpty) {
                  final batch = FirebaseFirestore.instance.batch();
                  for (final uid in _selectedUserIds) {
                    batch.update(
                      FirebaseFirestore.instance.collection('users').doc(uid),
                      updates,
                    );
                  }
                  await batch.commit();
                }
                if (dCtx.mounted) Navigator.pop(dCtx);
                if (mounted) {
                  setState(() => _selectedUserIds.clear());
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(
                      content: Text('تم تحديث التبعية والقسم بنجاح'),
                      backgroundColor: Color(0xFF10B981),
                    ),
                  );
                }
              },
              child: const Text(
                'تطبيق النقل',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
    affC.dispose();
    divC.dispose();
  }

  // ==================== تحرير بيانات موظف فردي ====================
  Future<void> _showEditUserDialog(
    String docId,
    Map<String, dynamic> data,
  ) async {
    final nameC = TextEditingController(text: userName(data, fallback: ''));
    final jobC = TextEditingController(text: userJob(data, fallback: ''));
    final affC = TextEditingController(
      text: userAffiliation(data, fallback: ''),
    );
    final divC = TextEditingController(text: userDivision(data, fallback: ''));
    final milC = TextEditingController(text: userMilitaryNumber(data));
    final daysC = TextEditingController(
      text: userTargetWorkDays(data, fallback: 10).toString(),
    );
    String role = normalizeRole(data['role'] as String?);
    final selectedZones = Set<String>.from(userZoneIds(data));

    await showDialog<void>(
      context: context,
      builder: (dCtx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: Text(
              'تعديل بيانات: ${userName(data)}',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _dialogField(nameC, 'الاسم الكامل'),
                    _dialogField(jobC, 'المسمى الوظيفي / الاختصاص'),
                    Row(
                      children: [
                        Expanded(child: _dialogField(affC, 'التبعية')),
                        const SizedBox(width: 8),
                        Expanded(child: _dialogField(divC, 'القسم / الفرقة')),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _dialogField(milC, 'الرقم الوظيفي / العسكري'),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _dialogField(
                            daysC,
                            'أيام الدوام المقررة',
                            keyboard: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 6,
                      children: [5, 10, 15, 20, 30, 0].map((d) {
                        final isSel = (int.tryParse(daysC.text) ?? -1) == d;
                        return ChoiceChip(
                          label: Text(
                            d == 0 ? 'مفتوح' : '$d أيام',
                            style: const TextStyle(fontSize: 10),
                          ),
                          selected: isSel,
                          selectedColor: const Color(0xFF0284C7),
                          backgroundColor: const Color(0xFF0F172A),
                          labelStyle: TextStyle(
                            color: isSel ? Colors.white : Colors.white70,
                          ),
                          onSelected: (_) =>
                              setLocal(() => daysC.text = d.toString()),
                        );
                      }).toList(),
                    ),
                    if (canManageZonesAndRoles(_currentUserRole)) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'الصلاحية:',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String>(
                        initialValue: role,
                        dropdownColor: const Color(0xFF0F172A),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'employee',
                            child: Text('موظف'),
                          ),
                          DropdownMenuItem(
                            value: 'supervisor',
                            child: Text('مشرف قسم'),
                          ),
                          DropdownMenuItem(
                            value: 'admin',
                            child: Text('مدير عام'),
                          ),
                          DropdownMenuItem(
                            value: 'owner',
                            child: Text('مالك النظام'),
                          ),
                        ],
                        onChanged: (v) =>
                            setLocal(() => role = v ?? 'employee'),
                      ),
                    ],
                    const SizedBox(height: 12),
                    const Text(
                      'مواقع الدوام المسموحة:',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _allZones.map((z) {
                        final isSel = selectedZones.contains(z.id);
                        return FilterChip(
                          label: Text(
                            z.name,
                            style: const TextStyle(fontSize: 11),
                          ),
                          selected: isSel,
                          selectedColor: const Color(0xFF0284C7),
                          checkmarkColor: Colors.white,
                          labelStyle: TextStyle(
                            color: isSel ? Colors.white : Colors.white70,
                          ),
                          backgroundColor: const Color(0xFF0F172A),
                          onSelected: (val) {
                            setLocal(() {
                              if (val) {
                                selectedZones.add(z.id);
                              } else if (selectedZones.length > 1) {
                                selectedZones.remove(z.id);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dCtx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                ),
                onPressed: () async {
                  final zList = selectedZones.toList();
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(docId)
                      .update({
                        'displayName': nameC.text.trim(),
                        'job': jobC.text.trim(),
                        'affiliation': affC.text.trim(),
                        'division': divC.text.trim(),
                        'militaryNumber': milC.text.trim(),
                        'targetWorkDays': int.tryParse(daysC.text.trim()) ?? 0,
                        'role': role,
                        'assignedZoneIds': zList,
                        'assignedZoneId': zList.first,
                      });
                  if (dCtx.mounted) Navigator.pop(dCtx);
                  if (mounted) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(
                        content: Text('تم حفظ تعديلات الموظف'),
                        backgroundColor: Color(0xFF10B981),
                      ),
                    );
                  }
                },
                child: const Text(
                  'حفظ التعديلات',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    nameC.dispose();
    jobC.dispose();
    affC.dispose();
    divC.dispose();
    milC.dispose();
    daysC.dispose();
  }

  // ==================== إدارة وحفظ مواقع العمل ====================
  Future<void> _createNewZoneDialog() async {
    final nameC = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dCtx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text(
            'إضافة موقع عمل جديد',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          content: _dialogField(
            nameC,
            'اسم الموقع (مثال: الفرع الشمالي / المستودع)',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
              ),
              onPressed: () async {
                if (nameC.text.trim().isEmpty) return;
                final newId = 'ZONE_${DateTime.now().millisecondsSinceEpoch}';
                final z = WorkZone(
                  id: newId,
                  name: nameC.text.trim(),
                  latitude: _defaultCenter.latitude,
                  longitude: _defaultCenter.longitude,
                  radiusMeters: 150,
                  durationDays: 10,
                );
                await FirebaseFirestore.instance
                    .collection('zones')
                    .doc(newId)
                    .set(z.toMap());
                if (dCtx.mounted) Navigator.pop(dCtx);
                await _loadAllZones(selectId: newId);
              },
              child: const Text(
                'إنشاء الموقع',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
    nameC.dispose();
  }

  Future<void> _saveZoneSettings() async {
    try {
      final lat = double.tryParse(_latController.text.trim()) ?? 0.0;
      final lng = double.tryParse(_lngController.text.trim()) ?? 0.0;
      final radius = double.tryParse(_radiusController.text.trim()) ?? 100.0;
      final grace = int.tryParse(_graceController.text.trim()) ?? 15;
      final durationDays =
          int.tryParse(_durationDaysController.text.trim()) ?? 10;
      final bssids = _bssidController.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final updated = WorkZone(
        id: _selectedZoneId,
        name: _zoneNameController.text.trim().isEmpty
            ? 'موقع عمل'
            : _zoneNameController.text.trim(),
        latitude: lat,
        longitude: lng,
        radiusMeters: radius,
        allowedBssids: bssids,
        shiftStart: _shiftStart,
        shiftEnd: _shiftEnd,
        graceMinutes: grace,
        workDays: _workDays,
        durationDays: durationDays,
      );

      await FirebaseFirestore.instance
          .collection('zones')
          .doc(_selectedZoneId)
          .set(updated.toMap(), SetOptions(merge: true));

      await _loadAllZones(selectId: _selectedZoneId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ إعدادات الموقع والدوام بنجاح'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء الحفظ: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _useCurrentGpsForZone() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition();
      setState(() {
        _latController.text = pos.latitude.toStringAsFixed(6);
        _lngController.text = pos.longitude.toStringAsFixed(6);
      });
      _mapController.move(LatLng(pos.latitude, pos.longitude), 16.5);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر جلب الموقع الحالي: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _appendCurrentWifiBssid() async {
    final bssid = await NetworkService.getCurrentBSSID();
    if (bssid == null || bssid.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تعذر قراءة بصمة الواي فاي الحالية (تأكد من الاتصال وتفعيل الموقع)',
            ),
            backgroundColor: Colors.orangeAccent,
          ),
        );
      }
      return;
    }
    final existing = _bssidController.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    existing.add(bssid);
    setState(() {
      _bssidController.text = existing.join(', ');
    });
  }

  // ==================== واجهة المستخدم الرئيسية ====================
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E293B),
          title: Row(
            children: [
              const Text(
                'لوحة القيادة والإدارة',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  roleArabicLabel(_currentUserRole),
                  style: const TextStyle(
                    color: Color(0xFF38BDF8),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(
                Icons.person_add_alt_1_rounded,
                color: Color(0xFF38BDF8),
              ),
              tooltip: 'إضافة موظف جديد',
              onPressed: _showAddAccountDialog,
            ),
            IconButton(
              icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
              tooltip: 'تسجيل الخروج',
              onPressed: () => AuthService().signOut(),
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFF38BDF8),
            labelColor: const Color(0xFF38BDF8),
            unselectedLabelColor: Colors.white60,
            tabs: const [
              Tab(icon: Icon(Icons.groups_rounded), text: 'الكادر والدوام'),
              Tab(icon: Icon(Icons.fact_check_rounded), text: 'سجل الحضور'),
              Tab(icon: Icon(Icons.map_rounded), text: 'المواقع والأوقات'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildPersonnelTab(),
            _buildAttendanceTab(),
            _buildZonesSettingsTab(),
          ],
        ),
      ),
    );
  }

  // ==================== التبويب 1: إدارة الكادر وتحديد أيام الدوام ====================
  Widget _buildPersonnelTab() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF38BDF8)),
          );
        }

        final allDocs = snapshot.data!.docs;
        final affiliations = <String>{'الكل'};
        final divisions = <String>{'الكل'};

        for (final d in allDocs) {
          final data = d.data();
          final aff = userAffiliation(data, fallback: '');
          final div = userDivision(data, fallback: '');
          if (aff.isNotEmpty) affiliations.add(aff);
          if (div.isNotEmpty) divisions.add(div);
        }

        final filteredDocs = allDocs.where((doc) {
          final u = doc.data();
          if (_currentUserRole == 'supervisor' &&
              _currentUserDivision.isNotEmpty) {
            if (userDivision(u, fallback: '') != _currentUserDivision)
              return false;
          }
          if (_filterAffiliation != 'الكل' &&
              userAffiliation(u) != _filterAffiliation) {
            return false;
          }
          if (_filterDivision != 'الكل' && userDivision(u) != _filterDivision) {
            return false;
          }
          if (_filterRole != 'الكل' &&
              normalizeRole(u['role'] as String?) != _filterRole) {
            return false;
          }
          if (_searchQuery.isNotEmpty) {
            final q = _searchQuery.toLowerCase();
            final haystack = [
              userName(u),
              userJob(u),
              userAffiliation(u),
              userDivision(u),
              userMilitaryNumber(u),
              u['email'] ?? '',
            ].join(' ').toLowerCase();
            if (!haystack.contains(q)) return false;
          }
          return true;
        }).toList();

        return Column(
          children: [
            // شريط البحث والفلاتر
            Container(
              padding: const EdgeInsets.all(12),
              color: const Color(0xFF1E293B),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _searchQuery = v.trim()),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'بحث بالاسم، الرقم الوظيفي، القسم، الاختصاص...',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 12,
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: Color(0xFF38BDF8),
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _miniDropdown(
                          label: 'التبعية',
                          value: affiliations.contains(_filterAffiliation)
                              ? _filterAffiliation
                              : 'الكل',
                          items: affiliations.toList(),
                          onChanged: (v) =>
                              setState(() => _filterAffiliation = v!),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _miniDropdown(
                          label: 'القسم',
                          value: divisions.contains(_filterDivision)
                              ? _filterDivision
                              : 'الكل',
                          items: divisions.toList(),
                          onChanged: (v) =>
                              setState(() => _filterDivision = v!),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: 'تحديد الكل في القائمة',
                        icon: Icon(
                          _selectedUserIds.length == filteredDocs.length &&
                                  filteredDocs.isNotEmpty
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded,
                          color: const Color(0xFF38BDF8),
                        ),
                        onPressed: () {
                          setState(() {
                            if (_selectedUserIds.length ==
                                filteredDocs.length) {
                              _selectedUserIds.clear();
                            } else {
                              _selectedUserIds
                                ..clear()
                                ..addAll(filteredDocs.map((d) => d.id));
                            }
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // شريط الإجراءات الجماعية عند تحديد موظفين
            if (_selectedUserIds.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'المحددون (${_selectedUserIds.length}):',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    ActionChip(
                      avatar: const Icon(
                        Icons.calendar_month_rounded,
                        size: 15,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'تحديد أيام الدوام',
                        style: TextStyle(fontSize: 11, color: Colors.white),
                      ),
                      backgroundColor: const Color(0xFF10B981),
                      onPressed: _showBulkWorkDaysDialog,
                    ),
                    ActionChip(
                      avatar: const Icon(
                        Icons.location_on_outlined,
                        size: 15,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'تعيين المواقع',
                        style: TextStyle(fontSize: 11, color: Colors.white),
                      ),
                      backgroundColor: const Color(0xFF0284C7),
                      onPressed: _showBulkAssignZonesDialog,
                    ),
                    ActionChip(
                      avatar: const Icon(
                        Icons.account_tree_outlined,
                        size: 15,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'نقل القسم/التبعية',
                        style: TextStyle(fontSize: 11, color: Colors.white),
                      ),
                      backgroundColor: const Color(0xFF6366F1),
                      onPressed: _showBulkDivisionDialog,
                    ),
                  ],
                ),
              ),

            // قائمة الموظفين
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: filteredDocs.length,
                itemBuilder: (context, index) {
                  final doc = filteredDocs[index];
                  final u = doc.data();
                  final isSelected = _selectedUserIds.contains(doc.id);
                  final isBlocked = u['isBlocked'] == true;
                  final targetDays = userTargetWorkDays(u, fallback: 0);
                  final uZoneIds = userZoneIds(u);
                  final zoneNames = _allZones
                      .where((z) => uZoneIds.contains(z.id))
                      .map((z) => z.name)
                      .join(' ، ');

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF38BDF8)
                            : Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      leading: Checkbox(
                        value: isSelected,
                        activeColor: const Color(0xFF38BDF8),
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _selectedUserIds.add(doc.id);
                            } else {
                              _selectedUserIds.remove(doc.id);
                            }
                          });
                        },
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              userName(u),
                              style: TextStyle(
                                color: isBlocked
                                    ? Colors.redAccent
                                    : Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              targetDays > 0
                                  ? 'دوام: $targetDays يوم'
                                  : 'دوام مفتوح',
                              style: const TextStyle(
                                color: Color(0xFF10B981),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${userJob(u)} • ${userSubtitle(u)}',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'المواقع: ${zoneNames.isEmpty ? "المقر الرئيسي" : zoneNames}',
                              style: const TextStyle(
                                color: Color(0xFF38BDF8),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      trailing: PopupMenuButton<String>(
                        color: const Color(0xFF0F172A),
                        icon: const Icon(
                          Icons.more_vert,
                          color: Colors.white70,
                        ),
                        onSelected: (action) async {
                          if (action == 'edit') {
                            await _showEditUserDialog(doc.id, u);
                          } else if (action == 'reset_device') {
                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(doc.id)
                                .update({'deviceId': FieldValue.delete()});
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('تم فك اقتران الجهاز بنجاح'),
                                  backgroundColor: Color(0xFF10B981),
                                ),
                              );
                            }
                          } else if (action == 'toggle_block') {
                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(doc.id)
                                .update({'isBlocked': !isBlocked});
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text(
                              'تعديل البيانات وأيام الدوام',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'reset_device',
                            child: Text(
                              'فك ارتباط الهاتف (Device ID)',
                              style: TextStyle(color: Colors.amber),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'toggle_block',
                            child: Text(
                              isBlocked
                                  ? 'إلغاء حظر الحساب'
                                  : 'إيقاف / حظر الحساب',
                              style: const TextStyle(color: Colors.redAccent),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // ==================== التبويب 2: سجل الحضور بنظام 12 ساعة بالعربي ====================
  Widget _buildAttendanceTab() {
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: const Color(0xFF1E293B),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now().add(const Duration(days: 30)),
                    );
                    if (picked != null) setState(() => _selectedDate = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_today,
                          size: 16,
                          color: Color(0xFF38BDF8),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          dateStr,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _miniDropdown(
                  label: 'الموقع',
                  value: _attendanceZoneFilter,
                  items: ['الكل', ..._allZones.map((z) => z.name)],
                  onChanged: (v) => setState(() => _attendanceZoneFilter = v!),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _miniDropdown(
                  label: 'الحالة',
                  value: _attendanceStatusFilter,
                  items: const ['الكل', 'منضبط', 'متأخر', 'قيد الدوام'],
                  onChanged: (v) =>
                      setState(() => _attendanceStatusFilter = v!),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('attendance_records')
                .where('dateString', isEqualTo: dateStr)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFF38BDF8)),
                );
              }

              final records = snapshot.data!.docs.where((d) {
                final data = d.data();
                if (_currentUserRole == 'supervisor' &&
                    _currentUserDivision.isNotEmpty) {
                  if ((data['userDivision'] ?? '') != _currentUserDivision)
                    return false;
                }
                if (_attendanceZoneFilter != 'الكل' &&
                    (data['zoneName'] ?? '') != _attendanceZoneFilter) {
                  return false;
                }
                final lateMins = (data['lateMinutes'] as num?)?.toInt() ?? 0;
                final status = data['status'] as String? ?? '';
                if (_attendanceStatusFilter == 'منضبط' && lateMins > 0)
                  return false;
                if (_attendanceStatusFilter == 'متأخر' && lateMins <= 0)
                  return false;
                if (_attendanceStatusFilter == 'قيد الدوام' &&
                    status != 'CHECKED_IN') {
                  return false;
                }
                return true;
              }).toList();

              if (records.isEmpty) {
                return Center(
                  child: Text(
                    'لا توجد سجلات حضور مطابقة ليوم $dateStr',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: records.length,
                itemBuilder: (context, i) {
                  final r = records[i].data();
                  final checkIn = r['checkIn'] as Map<String, dynamic>?;
                  final checkOut = r['checkOut'] as Map<String, dynamic>?;
                  final inTime = checkIn?['timestamp'] != null
                      ? formatTime12Ar(DateTime.parse(checkIn!['timestamp']))
                      : '--:--';
                  final outTime = checkOut?['timestamp'] != null
                      ? formatTime12Ar(DateTime.parse(checkOut!['timestamp']))
                      : 'قيد الدوام';
                  final lateMins = (r['lateMinutes'] as num?)?.toInt() ?? 0;
                  final shiftStartAr = formatShift12Ar(
                    (r['shiftStart'] as String?) ?? '08:00',
                  );
                  final shiftEndAr = formatShift12Ar(
                    (r['shiftEnd'] as String?) ?? '16:00',
                  );

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (r['userName'] as String?)?.isNotEmpty == true
                                    ? r['userName']
                                    : 'موظف (${r['userId']})',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'الموقع: ${r['zoneName'] ?? 'المقر'} • الوردية: $shiftStartAr - $shiftEndAr',
                                style: const TextStyle(
                                  color: Color(0xFF38BDF8),
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'الدخول: $inTime  |  الانصراف: $outTime',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${r['totalMinutes'] ?? 0} د',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: lateMins > 0
                                    ? Colors.orangeAccent.withValues(alpha: 0.2)
                                    : const Color(0xFF10B981)
                                          .withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                lateMins > 0 ? 'تأخير $lateMins د' : 'منضبط',
                                style: TextStyle(
                                  color: lateMins > 0
                                      ? Colors.orangeAccent
                                      : const Color(0xFF10B981),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ==================== التبويب 3: إعدادات المواقع والدوام بنظام 12 ساعة والأيام ====================
  Widget _buildZonesSettingsTab() {
    if (_isLoadingZone) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF38BDF8)),
      );
    }

    final lat = double.tryParse(_latController.text) ?? _defaultCenter.latitude;
    final lng =
        double.tryParse(_lngController.text) ?? _defaultCenter.longitude;
    final radius = double.tryParse(_radiusController.text) ?? 150.0;
    final centerPoint = LatLng(
      lat == 0 ? _defaultCenter.latitude : lat,
      lng == 0 ? _defaultCenter.longitude : lng,
    );

    const weekDaysMap = {
      6: 'السبت',
      7: 'الأحد',
      1: 'الإثنين',
      2: 'الثلاثاء',
      3: 'الأربعاء',
      4: 'الخميس',
      5: 'الجمعة',
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // اختيار موقع العمل أو إضافة موقع جديد
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _allZones.any((z) => z.id == _selectedZoneId)
                      ? _selectedZoneId
                      : _allZones.first.id,
                  dropdownColor: const Color(0xFF1E293B),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    labelText: 'موقع العمل المحدد',
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: _allZones
                      .map(
                        (z) =>
                            DropdownMenuItem(value: z.id, child: Text(z.name)),
                      )
                      .toList(),
                  onChanged: (val) {
                    if (val == null) return;
                    final found = _allZones.firstWhere((z) => z.id == val);
                    _populateZoneForm(found);
                    if (found.latitude != 0 && found.longitude != 0) {
                      _mapController.move(
                        LatLng(found.latitude, found.longitude),
                        16,
                      );
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                ),
                onPressed: _createNewZoneDialog,
                icon: const Icon(
                  Icons.add_location_alt_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                label: const Text(
                  'موقع جديد',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // خريطة تحديد السياج الجغرافي
          SizedBox(
            height: 220,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: centerPoint,
                  initialZoom: 15.5,
                  onTap: (_, point) {
                    setState(() {
                      _latController.text = point.latitude.toStringAsFixed(6);
                      _lngController.text = point.longitude.toStringAsFixed(6);
                    });
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.attendance.app',
                  ),
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: centerPoint,
                        radius: radius,
                        useRadiusInMeter: true,
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.22),
                        borderColor: const Color(0xFF38BDF8),
                        borderStrokeWidth: 2,
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: centerPoint,
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.redAccent,
                          size: 36,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          _dialogField(_zoneNameController, 'اسم موقع العمل'),
          Row(
            children: [
              Expanded(
                child: _dialogField(
                  _latController,
                  'خط العرض (Latitude)',
                  keyboard: TextInputType.number,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _dialogField(
                  _lngController,
                  'خط الطول (Longitude)',
                  keyboard: TextInputType.number,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                ),
                onPressed: _useCurrentGpsForZone,
                tooltip: 'التقاط موقعي الحالي',
                icon: const Icon(Icons.my_location, color: Colors.white),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _dialogField(
                  _radiusController,
                  'نصف قطر النطاق بالمتر',
                  keyboard: TextInputType.number,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _dialogField(
                  _graceController,
                  'سماحية التأخير (دقيقة)',
                  keyboard: TextInputType.number,
                ),
              ),
            ],
          ),

          // تحديد أوقات الوردية بنظام 12 ساعة بالعربي (ص / م)
          const SizedBox(height: 8),
          const Text(
            'أوقات الدوام الرسمي (بنظام 12 ساعة بالعربي):',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: Color(0xFF38BDF8)),
                  ),
                  onPressed: () => _pickShiftTime(isStart: true),
                  icon: const Icon(
                    Icons.wb_sunny_outlined,
                    color: Color(0xFF38BDF8),
                    size: 18,
                  ),
                  label: Text(
                    'البداية: ${formatShift12Ar(_shiftStart)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: Color(0xFF38BDF8)),
                  ),
                  onPressed: () => _pickShiftTime(isStart: false),
                  icon: const Icon(
                    Icons.nights_stay_outlined,
                    color: Color(0xFF38BDF8),
                    size: 18,
                  ),
                  label: Text(
                    'النهاية: ${formatShift12Ar(_shiftEnd)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),

          // تحديد مدة الدوام بالأيام للموقع
          const SizedBox(height: 14),
          const Text(
            'تحديد الدوام بالأيام (مثال: 10 أيام، 15 يوماً، أو 0 لمفتوح):',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          _dialogField(
            _durationDaysController,
            'عدد أيام الدوام المقررة في هذا الموقع',
            keyboard: TextInputType.number,
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [5, 10, 15, 20, 30, 0].map((d) {
              final isSel =
                  (int.tryParse(_durationDaysController.text) ?? -1) == d;
              return ChoiceChip(
                label: Text(d == 0 ? 'دوام مستمر (مفتوح)' : '$d أيام'),
                selected: isSel,
                selectedColor: const Color(0xFF0284C7),
                backgroundColor: const Color(0xFF1E293B),
                labelStyle: TextStyle(
                  color: isSel ? Colors.white : Colors.white70,
                  fontSize: 11,
                ),
                onSelected: (_) =>
                    setState(() => _durationDaysController.text = d.toString()),
              );
            }).toList(),
          ),

          // أيام الأسبوع المسموحة
          const SizedBox(height: 14),
          const Text(
            'أيام الدوام الأسبوعية:',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: weekDaysMap.entries.map((entry) {
              final selected = _workDays.contains(entry.key);
              return FilterChip(
                label: Text(entry.value, style: const TextStyle(fontSize: 11)),
                selected: selected,
                selectedColor: const Color(0xFF10B981),
                checkmarkColor: Colors.white,
                backgroundColor: const Color(0xFF1E293B),
                labelStyle: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                ),
                onSelected: (v) {
                  setState(() {
                    if (v) {
                      _workDays.add(entry.key);
                    } else if (_workDays.length > 1) {
                      _workDays.remove(entry.key);
                    }
                  });
                },
              );
            }).toList(),
          ),

          // بصمات الواي فاي BSSID
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _dialogField(
                  _bssidController,
                  'بصمات الواي فاي المعتمدة BSSID (مفصولة بفاصلة، اتركه فارغاً للتجاوز)',
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF1E293B),
                ),
                onPressed: _appendCurrentWifiBssid,
                tooltip: 'إضافة شبكة الواي فاي المتصل بها حالياً',
                icon: const Icon(
                  Icons.wifi_find_rounded,
                  color: Color(0xFF38BDF8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _saveZoneSettings,
              icon: const Icon(Icons.save_rounded, color: Colors.white),
              label: const Text(
                'حفظ إعدادات الموقع والدوام',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ==================== أدوات مساعدة للواجهة ====================
  Widget _dialogField(
    TextEditingController controller,
    String label, {
    bool obscure = false,
    TextInputType keyboard = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboard,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 12,
          ),
          filled: true,
          fillColor: const Color(0xFF0F172A),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
        ),
      ),
    );
  }

  Widget _miniDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(value) ? value : items.first,
          isExpanded: true,
          dropdownColor: const Color(0xFF1E293B),
          style: const TextStyle(color: Colors.white, fontSize: 12),
          items: items
              .map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Text('$label: $e', overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
