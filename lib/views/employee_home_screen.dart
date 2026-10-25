import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../bloc/attendance_cubit.dart';
import '../services/work_timer_controller.dart';
import '../services/auth_service.dart';
import '../core/services/user_fields.dart';

class EmployeeHomeScreen extends StatelessWidget {
  final String userId;
  const EmployeeHomeScreen({super.key, required this.userId});

  void _showHistorySheet(BuildContext context, int targetDays) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.65,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'سجل حضوري وأيام الدوام',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white54),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('attendance_records')
                          .where('userId', isEqualTo: userId)
                          .limit(60)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8)));
                        }
                        final docs = snapshot.data!.docs.toList();
                        docs.sort((a, b) {
                          final da = (a.data() as Map<String, dynamic>)['dateString'] ?? '';
                          final db = (b.data() as Map<String, dynamic>)['dateString'] ?? '';
                          return db.toString().compareTo(da.toString());
                        });

                        if (docs.isEmpty) {
                          return Center(
                            child: Text(
                              'لا توجد سجلات حضور سابقة',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                            ),
                          );
                        }

                        final totalMinutesAll = docs.fold<int>(
                          0,
                          (acc, d) => acc + (((d.data() as Map<String, dynamic>)['totalMinutes'] as num?)?.toInt() ?? 0),
                        );
                        final hours = totalMinutesAll ~/ 60;
                        final mins = totalMinutesAll % 60;

                        return Column(
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              margin: const EdgeInsets.only(bottom: 14),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.25)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  _statMini(
                                    'الأيام المنجزة',
                                    targetDays > 0 ? '${docs.length} من $targetDays يوم' : '${docs.length} يوم',
                                  ),
                                  _statMini('إجمالي الساعات', '$hours س و $mins د'),
                                ],
                              ),
                            ),
                            Expanded(
                              child: ListView.builder(
                                controller: scrollController,
                                itemCount: docs.length,
                                itemBuilder: (context, i) {
                                  final data = docs[i].data() as Map<String, dynamic>;
                                  final checkIn = data['checkIn'] as Map<String, dynamic>?;
                                  final checkOut = data['checkOut'] as Map<String, dynamic>?;
                                  final lateMins = (data['lateMinutes'] as num?)?.toInt() ?? 0;
                                  final zoneName = data['zoneName'] as String? ?? '';
                                  final inTime = checkIn?['timestamp'] != null
                                      ? formatTime12Ar(DateTime.parse(checkIn!['timestamp']))
                                      : '--:--';
                                  final outTime = checkOut?['timestamp'] != null
                                      ? formatTime12Ar(DateTime.parse(checkOut!['timestamp']))
                                      : 'قيد الدوام';

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0F172A),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(
                                                    data['dateString'] ?? '',
                                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                                  ),
                                                  if (zoneName.isNotEmpty) ...[
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      '($zoneName)',
                                                      style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'دخول: $inTime  •  انصراف: $outTime',
                                                style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              '${data['totalMinutes'] ?? 0} دقيقة',
                                              style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              lateMins > 0 ? 'تأخير $lateMins د' : 'منضبط',
                                              style: TextStyle(
                                                color: lateMins > 0 ? Colors.orangeAccent : const Color(0xFF10B981),
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _statMini(String label, String val) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
        const SizedBox(height: 4),
        Text(val, style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AttendanceCubit()..init(userId),
      child: BlocConsumer<AttendanceCubit, AttendanceState>(
        listener: (context, state) {
          if (state is AttendanceError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message, textDirection: TextDirection.rtl),
                backgroundColor: Colors.redAccent,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        builder: (context, state) {
          final targetDays = state is AttendanceLoaded ? state.targetWorkDays : 0;

          return Scaffold(
            backgroundColor: const Color(0xFF0F172A),
            appBar: AppBar(
              title: const Text('بوابة الحضور والانصراف', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              centerTitle: true,
              backgroundColor: const Color(0xFF1E293B),
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.history_rounded, color: Color(0xFF38BDF8)),
                tooltip: 'سجل حضوري',
                onPressed: () => _showHistorySheet(context, targetDays),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.my_location_rounded, color: Colors.white70),
                  tooltip: 'تحديث فحص الموقع والواي فاي',
                  onPressed: () => context.read<AttendanceCubit>().refreshTelemetry(autoPickNearest: true),
                ),
                IconButton(
                  icon: const Icon(Icons.logout, color: Colors.redAccent),
                  tooltip: 'تسجيل الخروج',
                  onPressed: () => AuthService().signOut(),
                ),
              ],
            ),
            body: Builder(
              builder: (context) {
                if (state is AttendanceLoading) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8)));
                }

                if (state is AttendanceLoaded) {
                  final isCheckedIn = state.record?.status == 'CHECKED_IN';
                  final isCompleted = state.record?.status == 'COMPLETED';
                  final user = state.userProfile;
                  final activeZone = state.selectedZone;
                  final distText = state.currentDistanceMeters != null
                      ? '${state.currentDistanceMeters!.toInt()} متر'
                      : 'قيد الفحص';

                  final remainingDays = (state.targetWorkDays - state.attendedDaysCount).clamp(0, 9999);
                  final progressValue = state.targetWorkDays > 0
                      ? (state.attendedDaysCount / state.targetWorkDays).clamp(0.0, 1.0)
                      : 0.0;

                  return Directionality(
                    textDirection: TextDirection.rtl,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      child: Column(
                        children: [
                          // بطاقة تعريف الموظف والتبعية والقسم
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor: const Color(0xFF38BDF8).withValues(alpha: 0.2),
                                  backgroundImage: userPhoto(user) != null ? NetworkImage(userPhoto(user)!) : null,
                                  child: userPhoto(user) == null
                                      ? const Icon(Icons.person, size: 24, color: Color(0xFF38BDF8))
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        userName(user, fallback: 'الموظف'),
                                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        [userJob(user), userAffiliation(user), userDivision(user)]
                                            .where((e) => e.isNotEmpty)
                                            .join(' • '),
                                        style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isCheckedIn
                                        ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                        : Colors.white.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    isCheckedIn ? 'على رأس العمل' : (isCompleted ? 'منصرف' : 'غير مسجل'),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isCheckedIn ? const Color(0xFF10B981) : Colors.white54,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),

                          // اختيار موقع العمل + أوقات الوردية بنظام 12 ساعة بالعربي
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.2)),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.business_rounded, color: Color(0xFF38BDF8), size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: state.assignedZones.length > 1
                                          ? DropdownButtonHideUnderline(
                                              child: DropdownButton<String>(
                                                value: activeZone.id,
                                                dropdownColor: const Color(0xFF1E293B),
                                                isDense: true,
                                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                                items: state.assignedZones
                                                    .map((z) => DropdownMenuItem(
                                                          value: z.id,
                                                          child: Text(z.name),
                                                        ))
                                                    .toList(),
                                                onChanged: (val) {
                                                  final found = state.assignedZones.firstWhere((z) => z.id == val);
                                                  context.read<AttendanceCubit>().selectZone(found);
                                                },
                                              ),
                                            )
                                          : Text(
                                              activeZone.name,
                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                            ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0F172A),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${formatShift12Ar(activeZone.shiftStart)} - ${formatShift12Ar(activeZone.shiftEnd)}',
                                        style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                                // شريط تقدم أيام الدوام المقررة (مثال: 10 أيام)
                                if (state.targetWorkDays > 0) ...[
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'خطة الدوام المحددة: ${state.targetWorkDays} أيام',
                                        style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                                      ),
                                      Text(
                                        'المنجز: ${state.attendedDaysCount} • المتبقي: $remainingDays يوم',
                                        style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: LinearProgressIndicator(
                                      value: progressValue,
                                      minHeight: 6,
                                      backgroundColor: const Color(0xFF0F172A),
                                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),

                          // شريط رادار التحقق الحي (المسافة + الواي فاي)
                          Row(
                            children: [
                              Expanded(
                                child: _telemetryBadge(
                                  icon: Icons.location_on_outlined,
                                  label: state.isInsideZone ? 'داخل النطاق ($distText)' : 'خارج النطاق ($distText)',
                                  isOk: state.isInsideZone,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _telemetryBadge(
                                  icon: Icons.wifi_rounded,
                                  label: state.isWifiConnected ? 'الشبكة مطابقة' : 'شبكة غير معتمدة',
                                  isOk: state.isWifiConnected,
                                ),
                              ),
                            ],
                          ),

                          if (state.pendingOfflineCount > 0) ...[
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () async {
                                final c = await context.read<AttendanceCubit>().syncOfflineNow();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('تمت مزامنة $c سجلات محفوظة'),
                                      backgroundColor: const Color(0xFF10B981),
                                    ),
                                  );
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.orangeAccent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.4)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.cloud_upload_outlined, color: Colors.orangeAccent, size: 16),
                                    const SizedBox(width: 8),
                                    Text(
                                      'لديك ${state.pendingOfflineCount} سجل بانتظار المزامنة (اضغط للرفع)',
                                      style: const TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],

                          const Spacer(),

                          // عداد الدوام الدائري المباشر
                          StreamBuilder<WorkTimerState>(
                            stream: context.read<AttendanceCubit>().timerController.stateStream,
                            initialData: WorkTimerState.initial(),
                            builder: (context, snapshot) {
                              final timerState = snapshot.data ?? WorkTimerState.initial();
                              return Container(
                                width: 210,
                                height: 210,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isCheckedIn ? const Color(0xFF38BDF8) : Colors.white12,
                                    width: 4,
                                  ),
                                  gradient: RadialGradient(
                                    colors: isCheckedIn
                                        ? [const Color(0xFF38BDF8).withValues(alpha: 0.15), Colors.transparent]
                                        : [Colors.white.withValues(alpha: 0.02), Colors.transparent],
                                  ),
                                  boxShadow: isCheckedIn
                                      ? [
                                          BoxShadow(
                                            color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                                            blurRadius: 30,
                                            spreadRadius: 2,
                                          )
                                        ]
                                      : null,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      isCheckedIn ? 'الوقت المنقضي' : (isCompleted ? 'اكتمل دوام اليوم' : 'العداد متوقف'),
                                      style: TextStyle(
                                        color: isCheckedIn ? const Color(0xFF38BDF8) : Colors.white38,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      isCompleted
                                          ? '${state.record!.totalMinutes} دقيقة'
                                          : timerState.formattedTime,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 32,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                    if (state.record != null) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        'الدخول: ${formatTime12Ar(state.record!.checkInTime)}',
                                        style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 11),
                                      ),
                                      if (state.record!.checkOutTime != null)
                                        Text(
                                          'الانصراف: ${formatTime12Ar(state.record!.checkOutTime!)}',
                                          style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10),
                                        ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: state.record!.isLate
                                              ? Colors.orangeAccent.withValues(alpha: 0.2)
                                              : const Color(0xFF10B981).withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          state.record!.isLate
                                              ? 'تأخير: ${state.record!.lateMinutes} د'
                                              : 'حضور منضبط',
                                          style: TextStyle(
                                            color: state.record!.isLate ? Colors.orangeAccent : const Color(0xFF10B981),
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
                          const Spacer(),

                          // زر التسجيل اليدوي
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isCheckedIn ? const Color(0xFFEF4444) : const Color(0xFF0284C7),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                elevation: 0,
                              ),
                              onPressed: () {
                                final cubit = context.read<AttendanceCubit>();
                                if (isCheckedIn) {
                                  cubit.triggerManualCheckOut(userId);
                                } else {
                                  cubit.triggerManualCheckIn(userId);
                                }
                              },
                              icon: Icon(isCheckedIn ? Icons.logout_rounded : Icons.login_rounded, color: Colors.white),
                              label: Text(
                                isCheckedIn
                                    ? 'تسجيل انصراف يدوي'
                                    : 'تسجيل حضور في (${activeZone.name})',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          );
        },
      ),
    );
  }

  Widget _telemetryBadge({required IconData icon, required String label, required bool isOk}) {
    final color = isOk ? const Color(0xFF10B981) : Colors.amber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}