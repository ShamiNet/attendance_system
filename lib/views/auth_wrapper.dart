import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../core/services/user_fields.dart';
import 'login_screen.dart';
import 'employee_home_screen.dart';
import 'admin_dashboard_screen.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();

    return StreamBuilder<User?>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF0F172A),
            body: Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8))),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          return const LoginScreen();
        }

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                backgroundColor: Color(0xFF0F172A),
                body: Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8))),
              );
            }

            final data = userSnapshot.data?.data();
            if (data != null && data['isBlocked'] == true) {
              return Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(
                  backgroundColor: const Color(0xFF0F172A),
                  body: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.block_rounded, color: Colors.redAccent, size: 68),
                          const SizedBox(height: 16),
                          const Text(
                            'تم إيقاف هذا الحساب',
                            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'يرجى مراجعة إدارة المنشأة لتفعيل حسابك.',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                            onPressed: () => authService.signOut(),
                            icon: const Icon(Icons.logout, color: Colors.white),
                            label: const Text('تسجيل الخروج', style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }

            final role = data?['role'] as String? ?? 'EMPLOYEE';
            if (isPrivilegedRole(role)) {
              return const AdminDashboardScreen();
            } else {
              return EmployeeHomeScreen(userId: user.uid);
            }
          },
        );
      },
    );
  }
}