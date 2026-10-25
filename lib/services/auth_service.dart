import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signInWithEmail(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
  }

  Future<FirebaseApp> _secondaryApp() async {
    for (final app in Firebase.apps) {
      if (app.name == 'account_creation') return app;
    }
    return Firebase.initializeApp(name: 'account_creation', options: Firebase.app().options);
  }

  Future<void> _createAccount({
    required String email,
    required String password,
    required String fullName,
    String jobTitle = 'موظف',
    String affiliation = 'الإدارة العامة',
    String division = 'القسم الرئيسي',
    String militaryNumber = '',
    String role = 'employee',
    int targetWorkDays = 10,
    List<String> assignedZoneIds = const ['ZONE_SCHOOL_MAIN'],
    required bool writeAsNewUser,
  }) async {
    final app = await _secondaryApp();
    final secondaryAuth = FirebaseAuth.instanceFor(app: app);
    try {
      final cred = await secondaryAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final db = writeAsNewUser ? FirebaseFirestore.instanceFor(app: app) : _firestore;
      final zones = assignedZoneIds.isEmpty ? ['ZONE_SCHOOL_MAIN'] : assignedZoneIds;

      await db.collection('users').doc(cred.user!.uid).set({
        'uid': cred.user!.uid,
        'id': cred.user!.uid,
        'displayName': fullName.trim(),
        'email': email.trim(),
        'job': jobTitle.trim().isEmpty ? 'موظف' : jobTitle.trim(),
        'affiliation': affiliation.trim().isEmpty ? 'الإدارة العامة' : affiliation.trim(),
        'division': division.trim().isEmpty ? 'القسم الرئيسي' : division.trim(),
        'militaryNumber': militaryNumber.trim(),
        'role': role,
        'targetWorkDays': targetWorkDays,
        'assignedZoneId': zones.first,
        'assignedZoneIds': zones,
        'isBlocked': false,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });
    } finally {
      await secondaryAuth.signOut();
    }
  }

  Future<void> registerEmployee({
    required String fullName,
    required String email,
    required String password,
  }) async {
    await _createAccount(
      email: email,
      password: password,
      fullName: fullName,
      role: 'owner',
      targetWorkDays: 0,
      writeAsNewUser: true,
    );
    await signInWithEmail(email, password);
  }

  Future<void> createAccountByAdmin({
    required String fullName,
    required String email,
    required String password,
    required String jobTitle,
    String affiliation = 'الإدارة العامة',
    String division = 'القسم الرئيسي',
    String militaryNumber = '',
    String role = 'employee',
    int targetWorkDays = 10,
    List<String> assignedZoneIds = const ['ZONE_SCHOOL_MAIN'],
  }) {
    return _createAccount(
      email: email,
      password: password,
      fullName: fullName,
      jobTitle: jobTitle,
      affiliation: affiliation,
      division: division,
      militaryNumber: militaryNumber,
      role: role,
      targetWorkDays: targetWorkDays,
      assignedZoneIds: assignedZoneIds,
      writeAsNewUser: false,
    );
  }

  static String friendlyError(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'email-already-in-use':
          return 'هذا البريد مستخدم مسبقاً';
        case 'invalid-email':
          return 'صيغة البريد الإلكتروني غير صحيحة';
        case 'weak-password':
          return 'كلمة المرور ضعيفة (6 أحرف على الأقل)';
        case 'invalid-credential':
        case 'wrong-password':
        case 'user-not-found':
          return 'بيانات الدخول غير صحيحة';
        case 'network-request-failed':
          return 'تعذر الاتصال بالإنترنت';
      }
    }
    return e.toString().replaceAll('Exception: ', '');
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  Future<String> getUserRole(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        return doc.data()!['role'] ?? 'employee';
      }
    } catch (_) {}
    return 'employee';
  }
}