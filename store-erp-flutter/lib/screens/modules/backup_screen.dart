import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../data/database_helper.dart';
import '../../providers/app_provider.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final _db = DatabaseHelper.instance;
  final _folder = TextEditingController();
  final _filename = TextEditingController(text: 'store_backup');
  final _restorePath = TextEditingController();
  final _time = TextEditingController(text: '02:00');
  List<Map<String, Object?>> _history = [];
  bool _copyOnly = true, _verify = true, _daily = false;
  bool _verifyDaily = true, _copyOnlyDaily = true, _safetyBackup = true;
  bool _busy = false;
  double? _progress;
  String _status = 'جاهز';
  String? _settingsPath;

  @override
  void initState() { super.initState(); _initialize(); }
  @override
  void dispose() { _folder.dispose(); _filename.dispose(); _restorePath.dispose(); _time.dispose(); super.dispose(); }

  void _message(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _initialize() async {
    final dir = await getApplicationSupportDirectory();
    final backupDir = Directory(p.join(dir.path, 'backups'));
    await backupDir.create(recursive: true);
    _folder.text = backupDir.path;
    _settingsPath = p.join(dir.path, 'backup_settings.json');
    try {
      final s = jsonDecode(await File(_settingsPath!).readAsString()) as Map<String, dynamic>;
      _folder.text = (s['folder'] ?? _folder.text).toString();
      _filename.text = (s['filename'] ?? _filename.text).toString();
      _time.text = (s['time'] ?? _time.text).toString();
      _copyOnly = s['copyOnly'] as bool? ?? true;
      _verify = s['verify'] as bool? ?? true;
      _daily = s['daily'] as bool? ?? false;
      _verifyDaily = s['verifyDaily'] as bool? ?? true;
      _copyOnlyDaily = s['copyOnlyDaily'] as bool? ?? true;
      _safetyBackup = s['safetyBackup'] as bool? ?? true;
    } catch (_) {}
    if (mounted) setState(() {});
    await _reloadHistory();
  }

  Future<void> _reloadHistory() async {
    try {
      final rows = await _db.query('backup_history', orderBy: 'created_at DESC', limit: 100);
      if (mounted) setState(() => _history = rows);
    } catch (e) { _message('تعذر تحميل فهرس النسخ: $e'); }
  }

  Future<void> _saveSettings() async {
    final time = _time.text.trim();
    if (!RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(time)) {
      _message('أدخل وقتًا صحيحًا بصيغة HH:MM'); return;
    }
    try {
      await File(_settingsPath!).writeAsString(jsonEncode({
        'folder': _folder.text.trim(), 'filename': _filename.text.trim(), 'time': time,
        'copyOnly': _copyOnly, 'verify': _verify, 'daily': _daily,
        'verifyDaily': _verifyDaily, 'copyOnlyDaily': _copyOnlyDaily, 'safetyBackup': _safetyBackup,
      }));
      _message('حُفظت الإعدادات محليًا. الجدولة اليومية محفوظة كإعداد فقط؛ لا تعمل في الخلفية عند إغلاق التطبيق.');
    } catch (e) { _message('تعذر حفظ الإعدادات: $e'); }
  }

  Future<void> _browseFolder() async {
    final path = await FilePicker.platform.getDirectoryPath(dialogTitle: 'اختر مجلد حفظ النسخ');
    if (path != null && mounted) setState(() => _folder.text = path);
  }

  Future<void> _browseRestoreFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'اختر ملف النسخة الاحتياطية', type: FileType.custom,
      allowedExtensions: ['db', 'sqlite', 'sqlite3'], allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path != null && mounted) setState(() => _restorePath.text = path);
  }

  Future<bool> _createBackup({bool safety = false}) async {
    if (_busy) return false;
    final directoryPath = _folder.text.trim();
    final rawName = _filename.text.trim();
    if (directoryPath.isEmpty || rawName.isEmpty) { _message('حدد مجلد الحفظ واسم الملف أولًا'); return false; }
    final safeName = p.basenameWithoutExtension(rawName).replaceAll(RegExp(r'[^a-zA-Z0-9_\-\u0600-\u06FF]'), '_');
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
    final name = safety ? 'safety_$stamp.db' : '${safeName}_$stamp.db';
    setState(() { _busy = true; _progress = 0.1; _status = 'تجهيز قاعدة البيانات...'; });
    try {
      final directory = Directory(directoryPath);
      await directory.create(recursive: true);
      await _db.prepareForBackup();
      final source = File(await _db.databasePath);
      if (!await source.exists()) throw StateError('لم يتم العثور على ملف قاعدة البيانات');
      setState(() { _progress = 0.45; _status = 'نسخ قاعدة البيانات...'; });
      final target = await source.copy(p.join(directory.path, name));
      setState(() { _progress = 0.8; _status = 'التحقق من الملف...'; });
      if (_verify || safety) {
        await _db.verifyDatabaseFile(target.path);
      }
      await _db.insert('backup_history', {'file_path': target.path, 'status': 'نجاح'});
      if (mounted) setState(() { _progress = 1; _status = 'اكتملت النسخة: ${target.path}'; });
      await _reloadHistory();
      _message(safety ? 'تم إنشاء نسخة الأمان قبل الاسترجاع' : 'تم إنشاء النسخة الاحتياطية بنجاح');
      return true;
    } catch (e) {
      if (mounted) setState(() => _status = 'فشلت العملية: $e');
      _message('تعذر إنشاء النسخة الاحتياطية: $e');
      return false;
    } finally { if (mounted) setState(() { _busy = false; _progress = null; }); }
  }

  Future<void> _restore() async {
    if (_busy) return;
    final path = _restorePath.text.trim();
    if (path.isEmpty || !await File(path).exists()) { _message('اختر ملف نسخة احتياطية موجودًا أولًا'); return; }
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('تأكيد استرجاع قاعدة البيانات'),
      content: const Text('سيتم استبدال قاعدة البيانات الحالية. تأكد من اختيار النسخة الصحيحة.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('استرجاع')),
      ],
    ));
    if (confirmed != true || !mounted) return;
    if (_safetyBackup) {
      final safetyCreated = await _createBackup(safety: true);
      if (!safetyCreated) {
        if (mounted) _message('أُلغي الاسترجاع لأن إنشاء نسخة الأمان لم ينجح. قاعدة البيانات الحالية لم تُستبدل.');
        return;
      }
    }
    if (!mounted) return;
    setState(() { _busy = true; _progress = 0.2; _status = 'التحقق من النسخة واستبدال قاعدة البيانات...'; });
    try {
      await _db.restoreDatabaseFrom(path);
      await _reloadHistory();
      if (mounted) setState(() => _status = 'اكتمل الاسترجاع من: $path');
      _message('تم استرجاع قاعدة البيانات. راجع البيانات قبل متابعة العمل.');
    } catch (e) {
      if (mounted) setState(() => _status = 'فشل الاسترجاع: $e');
      _message('تعذر استرجاع النسخة: $e');
    } finally { if (mounted) setState(() { _busy = false; _progress = null; }); }
  }

  Future<void> _openFolder() async {
    final path = _folder.text.trim();
    if (path.isEmpty) return;
    try {
      await Directory(path).create(recursive: true);
      if (Platform.isWindows) { await Process.start('explorer.exe', [path]); }
      else if (Platform.isMacOS) { await Process.start('open', [path]); }
      else if (Platform.isLinux) { await Process.start('xdg-open', [path]); }
      else { _message('فتح المجلد غير مدعوم على هذا النظام'); }
    } catch (e) { _message('تعذر فتح المجلد: $e'); }
  }

  Widget _section(String title, IconData icon, List<Widget> children) => Card(
    child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [Icon(icon), const SizedBox(width: 8), Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))]),
      const Divider(height: 24), ...children,
    ])),
  );

  Widget _check(String label, bool value, ValueChanged<bool?> changed) => CheckboxListTile(
    contentPadding: EdgeInsets.zero, dense: true, value: value, onChanged: _busy ? null : changed,
    title: Text(label), controlAffinity: ListTileControlAffinity.leading,
  );

  Widget _info(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [SizedBox(width: 150, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))), Expanded(child: SelectableText(value))]),
  );

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
    Row(children: [
      const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('النسخ الاحتياطي والاسترجاع', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
        SizedBox(height: 4), Text('إدارة نسخ قاعدة بيانات SQLite المحلية وحفظها واسترجاعها'),
      ])),
      Chip(avatar: const Icon(Icons.shield_outlined, size: 18), label: Text(_busy ? 'قيد التنفيذ' : 'جاهز')),
    ]),
    const SizedBox(height: 14),
    _section('معلومات الاتصال', Icons.storage, [
      _info('الخادم', 'قاعدة بيانات محلية على هذا الجهاز'),
      _info('قاعدة البيانات', 'local_store.db'),
      _info('نوع المصادقة', 'مصادقة التطبيق'),
      _info('المستخدم النشط', context.watch<AppProvider>().currentUser.isEmpty ? '—' : context.watch<AppProvider>().currentUser),
      const SizedBox(height: 6),
      const Text('النسخ يحفظ ملف قاعدة البيانات المحلي ولا يرسل البيانات إلى خادم خارجي.', style: TextStyle(color: Colors.blueGrey)),
    ]),
    _section('إنشاء نسخة احتياطية', Icons.backup_outlined, [
      TextField(controller: _folder, decoration: InputDecoration(labelText: 'مجلد الحفظ الافتراضي', border: const OutlineInputBorder(), suffixIcon: IconButton(tooltip: 'استعراض المجلد', onPressed: _busy ? null : _browseFolder, icon: const Icon(Icons.folder_open)))),
      const SizedBox(height: 10),
      TextField(controller: _filename, decoration: const InputDecoration(labelText: 'اسم الملف', border: OutlineInputBorder())),
      _check('نسخة Copy Only', _copyOnly, (v) => setState(() => _copyOnly = v ?? false)),
      _check('التحقق من الملف بعد الإنشاء', _verify, (v) => setState(() => _verify = v ?? false)),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(onPressed: _busy ? null : () => _createBackup(), icon: const Icon(Icons.save_alt), label: const Text('إنشاء النسخة الآن')),
        OutlinedButton.icon(onPressed: _busy ? null : _openFolder, icon: const Icon(Icons.folder_open), label: const Text('فتح المجلد')),
      ]),
    ]),
    _section('النسخ التلقائي', Icons.schedule, [
      _check('تفعيل النسخ اليومي', _daily, (v) => setState(() => _daily = v ?? false)),
      TextField(controller: _time, decoration: const InputDecoration(labelText: 'وقت التشغيل (HH:MM)', border: OutlineInputBorder())),
      _check('التحقق من النسخة يوميًا', _verifyDaily, (v) => setState(() => _verifyDaily = v ?? false)),
      _check('استخدام Copy Only للنسخ اليومي', _copyOnlyDaily, (v) => setState(() => _copyOnlyDaily = v ?? false)),
      const Text('يتم حفظ إعدادات الجدولة محليًا. التنفيذ التلقائي عند إغلاق التطبيق يحتاج خدمة مجدولة مستقلة.', style: TextStyle(color: Colors.deepOrange)),
      Wrap(spacing: 8, children: [
        OutlinedButton.icon(onPressed: _busy ? null : _saveSettings, icon: const Icon(Icons.settings), label: const Text('حفظ الإعدادات')),
        OutlinedButton.icon(onPressed: _busy ? null : () => _createBackup(), icon: const Icon(Icons.play_arrow), label: const Text('تشغيل الآن')),
      ]),
    ]),
    _section('استرجاع نسخة', Icons.settings_backup_restore, [
      TextField(controller: _restorePath, decoration: InputDecoration(labelText: 'ملف الاسترجاع', border: const OutlineInputBorder(), suffixIcon: IconButton(tooltip: 'استعراض الملفات', onPressed: _busy ? null : _browseRestoreFile, icon: const Icon(Icons.attach_file)))),
      _check('إنشاء نسخة أمان قبل الاسترجاع', _safetyBackup, (v) => setState(() => _safetyBackup = v ?? false)),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(onPressed: _busy ? null : _restore, icon: const Icon(Icons.restore), label: const Text('بدء الاسترجاع')),
        OutlinedButton.icon(onPressed: _busy || _history.isEmpty ? null : () => setState(() => _restorePath.text = (_history.first['file_path'] ?? '').toString()), icon: const Icon(Icons.history), label: const Text('استخدام النسخة المحددة')),
      ]),
    ]),
    _section('فهرس النسخ الاحتياطية', Icons.list_alt, [
      Row(children: [
        Expanded(child: Text('النسخ المسجلة: ${_history.length}')),
        IconButton(tooltip: 'تحديث القائمة', onPressed: _busy ? null : _reloadHistory, icon: const Icon(Icons.refresh)),
      ]),
      if (_history.isEmpty) const Padding(padding: EdgeInsets.all(18), child: Center(child: Text('لا توجد نسخ مسجلة بعد')))
      else SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(columns: const [
        DataColumn(label: Text('المسار')), DataColumn(label: Text('تاريخ الإنشاء')), DataColumn(label: Text('الحالة')), DataColumn(label: Text('إجراء')),
      ], rows: _history.map((row) => DataRow(cells: [
        DataCell(ConstrainedBox(constraints: const BoxConstraints(maxWidth: 320), child: SelectableText((row['file_path'] ?? '').toString()))),
        DataCell(Text((row['created_at'] ?? '—').toString())),
        DataCell(Text((row['status'] ?? '—').toString())),
        DataCell(TextButton(onPressed: _busy ? null : () => setState(() => _restorePath.text = (row['file_path'] ?? '').toString()), child: const Text('استخدام'))),
      ])).toList())),
    ]),
    if (_progress != null) ...[const SizedBox(height: 8), LinearProgressIndicator(value: _progress)],
    Card(child: Padding(padding: const EdgeInsets.all(14), child: Text(_status, style: const TextStyle(fontWeight: FontWeight.w500)))),
    Align(alignment: AlignmentDirectional.centerEnd, child: TextButton.icon(onPressed: () => Navigator.maybePop(context), icon: const Icon(Icons.close), label: const Text('خروج'))),
  ]);
}
