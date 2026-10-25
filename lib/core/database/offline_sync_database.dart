import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class OfflineSyncDatabase {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB('offline_attendance.db');
    return _db!;
  }

  static Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE attendance_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            userId TEXT NOT NULL,
            zoneId TEXT,
            actionType TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            method TEXT NOT NULL,
            bssid TEXT,
            deviceId TEXT NOT NULL,
            isSynced INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
    );
  }

  static Future<int> queueAttendance(Map<String, dynamic> record) async {
    final db = await database;
    return await db.insert('attendance_queue', record);
  }

  static Future<List<Map<String, dynamic>>> getUnsyncedRecords() async {
    final db = await database;
    return await db.query(
      'attendance_queue',
      where: 'isSynced = ?',
      whereArgs: [0],
      orderBy: 'id ASC',
    );
  }

  static Future<int> markAsSynced(int id) async {
    final db = await database;
    return await db.update(
      'attendance_queue',
      {'isSynced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}