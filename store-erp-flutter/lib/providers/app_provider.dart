import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../data/database_helper.dart';

class AppProvider extends ChangeNotifier {
  final db = DatabaseHelper.instance;
  String currentUser = 'أحمد علي';
  String currentRoles = '';
  bool loggedIn = false;
  int refreshVersion = 0;
  Future<List<Map<String,Object?>>> load(String table) => db.query(table, orderBy: 'id DESC');
  Future<void> refresh() async { refreshVersion++; notifyListeners(); }
  String _passwordDigest(String password) => sha256.convert(utf8.encode(password)).toString();
  Future<void> signIn(String username, String password) async {
    final rows = await db.query('users', where: 'username=? AND is_active=1', whereArgs: [username]);
    if (rows.isEmpty) throw StateError('اسم المستخدم أو كلمة المرور غير صحيحة');
    final stored = rows.first['password_hash']?.toString() ?? '';
    final valid = stored == _passwordDigest(password) || stored == password;
    if (!valid) throw StateError('اسم المستخدم أو كلمة المرور غير صحيحة');
    // Upgrade legacy plain-text seed/credentials after a successful login.
    if (stored == password) await db.update('users', {'password_hash':_passwordDigest(password)}, where:'id=?', whereArgs:[rows.first['id']]);
    currentUser = rows.first['full_name'] as String? ?? username;
    currentRoles = (rows.first['roles'] ?? '').toString();
    loggedIn = true;
    notifyListeners();
  }
  Future<int> create(String table, Map<String,Object?> data) async { final id = await db.insert(table,data); await refresh(); return id; }
  Future<void> edit(String table, int id, Map<String,Object?> data) async { await db.update(table,data,where:'id=?',whereArgs:[id]); await refresh(); }
  Future<void> remove(String table, int id) async { await db.delete(table,where:'id=?',whereArgs:[id]); await refresh(); }
}
