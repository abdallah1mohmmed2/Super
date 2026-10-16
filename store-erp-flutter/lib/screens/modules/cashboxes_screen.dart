import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database_helper.dart';
import '../../providers/app_provider.dart';

class CashBoxesScreen extends StatefulWidget {
  const CashBoxesScreen({super.key});

  @override
  State<CashBoxesScreen> createState() => _CashBoxesScreenState();
}

class _CashBoxesScreenState extends State<CashBoxesScreen> {
  final _db = DatabaseHelper.instance;
  final _name = TextEditingController();
  final _search = TextEditingController();
  List<Map<String, Object?>> _boxes = [];
  List<Map<String, Object?>> _transactions = [];
  List<Map<String, Object?>> _sessions = [];
  int? _boxId;
  int? _sessionId;
  bool _active = true;
  bool _busy = false;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _name.dispose();
    _search.dispose();
    super.dispose();
  }

  void _message(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _stamp() => DateTime.now().toUtc().toIso8601String().replaceFirst('T', ' ').substring(0, 19);
  String _money(Object? value) => ((value as num?)?.toDouble() ?? 0).toStringAsFixed(2);
  Map<String, Object?>? get _selectedBox {
    for (final box in _boxes) {
      if ((box['id'] as num).toInt() == _boxId) return box;
    }
    return null;
  }

  Map<String, Object?>? get _activeSession {
    for (final session in _sessions) {
      if ((session['cash_box_id'] as num?)?.toInt() == _boxId && session['status'] == 'مفتوحة') return session;
    }
    return null;
  }

  Future<void> _reload() async {
    try {
      final boxes = await _db.query('cash_boxes', orderBy: 'name COLLATE NOCASE');
      final sessions = await _db.query('cash_sessions', orderBy: 'opened_at DESC');
      final selected = _boxId ?? (boxes.isEmpty ? null : (boxes.first['id'] as num).toInt());
      final transactions = selected == null
          ? <Map<String, Object?>>[]
          : await _db.query('cash_box_transactions', where: 'cash_box_id=?', whereArgs: [selected], orderBy: 'transaction_date DESC', limit: 300);
      if (!mounted) return;
      setState(() {
        _boxes = boxes;
        _sessions = sessions;
        _boxId = boxes.any((b) => (b['id'] as num).toInt() == selected) ? selected : (boxes.isEmpty ? null : (boxes.first['id'] as num).toInt());
        _transactions = transactions;
        if (_boxId != null && boxes.any((b) => (b['id'] as num).toInt() == _boxId)) {
          final row = boxes.firstWhere((b) => (b['id'] as num).toInt() == _boxId);
          _name.text = (row['name'] ?? '').toString();
          _active = ((row['is_active'] as num?)?.toInt() ?? 1) == 1;
        }
        if (_sessionId != null && !sessions.any((s) => (s['id'] as num).toInt() == _sessionId)) _sessionId = null;
      });
    } catch (e) {
      _message('تعذر تحميل بيانات الصناديق: $e');
    }
  }

  void _newBox() {
    setState(() {
      _boxId = null;
      _name.clear();
      _active = true;
    });
  }

  Future<void> _saveBox() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _message('اسم الصندوق مطلوب');
      return;
    }
    setState(() => _busy = true);
    try {
      final data = <String, Object?>{'name': name, 'is_active': _active ? 1 : 0};
      if (_boxId == null) {
        _boxId = await _db.insert('cash_boxes', data);
      } else {
        await _db.update('cash_boxes', data, where: 'id=?', whereArgs: [_boxId]);
      }
      await context.read<AppProvider>().refresh();
      await _reload();
      if (mounted) _message('تم حفظ بيانات الصندوق. الرصيد لا يُعدّل يدويًا؛ يتغير عبر الحركات المرحلة.');
    } catch (e) {
      _message('تعذر حفظ الصندوق: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSession() async {
    final box = _selectedBox;
    if (box == null) {
      _message('أنشئ صندوقًا وحدده أولًا');
      return;
    }
    if (((box['is_active'] as num?)?.toInt() ?? 0) != 1) {
      _message('لا يمكن فتح جلسة لصندوق غير نشط');
      return;
    }
    if (_activeSession != null) {
      _message('توجد جلسة مفتوحة لهذا الصندوق بالفعل');
      return;
    }
    setState(() => _busy = true);
    try {
      final now = _stamp();
      final opening = (box['balance'] as num?)?.toDouble() ?? 0;
      final id = await _db.insert('cash_sessions', {
        'cash_box_id': _boxId,
        'session_no': 'CS-${DateTime.now().millisecondsSinceEpoch}',
        'opened_at': now,
        'opening_balance': opening,
        'status': 'مفتوحة',
        'opened_by': context.read<AppProvider>().currentUser,
      });
      await _db.insert('audit_log', {
        'action': 'فتح جلسة صندوق',
        'entity': 'cash_sessions',
        'entity_id': id,
        'details': 'الصندوق: ${box['name']}؛ الرصيد الافتتاحي: ${opening.toStringAsFixed(2)}',
      });
      await _reload();
      if (mounted) _message('تم فتح جلسة الصندوق برصيد افتتاحي ${opening.toStringAsFixed(2)}');
    } catch (e) {
      _message('تعذر فتح الجلسة: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _closeSession() async {
    final session = _activeSession;
    final box = _selectedBox;
    if (session == null || box == null) {
      _message('لا توجد جلسة مفتوحة لهذا الصندوق');
      return;
    }
    final actualController = TextEditingController();
    final notesController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إقفال جلسة الصندوق'),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('الصندوق: ${box['name']}'),
            Text('الرصيد الافتتاحي: ${_money(session['opening_balance'])}'),
            const SizedBox(height: 10),
            TextField(controller: actualController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'الرصيد الفعلي عند العد')),
            const SizedBox(height: 10),
            TextField(controller: notesController, maxLines: 2, decoration: const InputDecoration(labelText: 'ملاحظات الإقفال')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد الإقفال')),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      actualController.dispose();
      notesController.dispose();
      return;
    }
    final actual = double.tryParse(actualController.text.trim());
    if (actual == null || actual < 0) {
      _message('أدخل رصيدًا فعليًا صحيحًا غير سالب');
      actualController.dispose();
      notesController.dispose();
      return;
    }
    setState(() => _busy = true);
    try {
      final movements = await _db.query(
        'cash_box_transactions',
        where: 'cash_box_id=? AND transaction_date>=?',
        whereArgs: [_boxId, session['opened_at']],
      );
      final movementTotal = movements.fold<double>(0, (sum, row) => sum + ((row['amount'] as num?)?.toDouble() ?? 0));
      final opening = (session['opening_balance'] as num?)?.toDouble() ?? 0;
      final expected = opening + movementTotal;
      final difference = actual - expected;
      final now = _stamp();
      await _db.update('cash_sessions', {
        'closed_at': now,
        'expected_balance': expected,
        'actual_balance': actual,
        'difference': difference,
        'status': 'مغلقة',
        'closed_by': context.read<AppProvider>().currentUser,
        'notes': notesController.text.trim(),
      }, where: 'id=? AND status=?', whereArgs: [session['id'], 'مفتوحة']);
      await _db.insert('audit_log', {
        'action': 'إقفال جلسة صندوق',
        'entity': 'cash_sessions',
        'entity_id': session['id'],
        'details': 'متوقع=${expected.toStringAsFixed(2)}؛ فعلي=${actual.toStringAsFixed(2)}؛ فرق=${difference.toStringAsFixed(2)}',
      });
      await _reload();
      if (mounted) {
        await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
          title: const Text('ملخص إقفال الصندوق'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('الرصيد الافتتاحي: ${opening.toStringAsFixed(2)}'),
            Text('صافي الحركات: ${movementTotal.toStringAsFixed(2)}'),
            Text('الرصيد النظامي: ${expected.toStringAsFixed(2)}'),
            Text('الرصيد الفعلي: ${actual.toStringAsFixed(2)}'),
            Text('الفرق: ${difference.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, color: difference.abs() < 0.005 ? Colors.green : Colors.deepOrange)),
            Text(difference.abs() < 0.005 ? 'حالة الفرق: مطابق' : difference > 0 ? 'حالة الفرق: زيادة' : 'حالة الفرق: عجز'),
          ]),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('موافق'))],
        ));
      }
    } catch (e) {
      _message('تعذر إقفال الجلسة: $e');
    } finally {
      actualController.dispose();
      notesController.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleBoxes = _boxes.where((box) => _filter.isEmpty || (box['name'] ?? '').toString().toLowerCase().contains(_filter.toLowerCase())).toList();
    final box = _selectedBox;
    final session = _activeSession;
    final expected = session == null ? null : (session['opening_balance'] as num?)?.toDouble();
    return ListView(padding: const EdgeInsets.all(18), children: [
      Row(children: [
        const Expanded(child: Text('إدارة الصناديق وإقفال الجلسة', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
        OutlinedButton.icon(onPressed: _busy ? null : _reload, icon: const Icon(Icons.refresh), label: const Text('تحديث')),
        const SizedBox(width: 8),
        FilledButton.icon(onPressed: _busy ? null : _newBox, icon: const Icon(Icons.add), label: const Text('صندوق جديد')),
      ]),
      const SizedBox(height: 12),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_boxId == null ? 'بيانات صندوق جديد' : 'بيانات الصندوق #$_boxId', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(width: 320, child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'اسم الصندوق'))),
          SizedBox(width: 180, child: SwitchListTile(value: _active, onChanged: (v) => setState(() => _active = v), title: const Text('الصندوق نشط'), contentPadding: EdgeInsets.zero)),
          SizedBox(width: 180, child: InputDecorator(decoration: const InputDecoration(labelText: 'الرصيد الحالي'), child: Text(_money(box?['balance'])))),
          FilledButton.icon(onPressed: _busy ? null : _saveBox, icon: const Icon(Icons.save_outlined), label: const Text('حفظ الصندوق')),
        ]),
        const SizedBox(height: 10),
        Text('الرصيد الحالي للعرض فقط، ويُحدّث تلقائيًا عند ترحيل المبيعات والمشتريات والتحويلات.', style: TextStyle(color: Colors.blueGrey.shade700)),
      ]))),
      const SizedBox(height: 12),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('جلسة الصندوق', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(width: 300, child: DropdownButtonFormField<int>(value: _boxes.any((b) => (b['id'] as num).toInt() == _boxId) ? _boxId : null, decoration: const InputDecoration(labelText: 'الصندوق'), items: _boxes.map((b) => DropdownMenuItem(value: (b['id'] as num).toInt(), child: Text((b['name'] ?? '').toString()))).toList(), onChanged: _busy ? null : (v) async { setState(() => _boxId = v); await _reload(); })),
          Chip(label: Text(session == null ? 'لا توجد جلسة مفتوحة' : 'جلسة مفتوحة: ${session['session_no']}')),
          if (session != null) Text('وقت الفتح: ${session['opened_at']}'),
          if (expected != null) Text('الرصيد الافتتاحي: ${expected.toStringAsFixed(2)}'),
          FilledButton.icon(onPressed: _busy || session != null || box == null ? null : _openSession, icon: const Icon(Icons.lock_open), label: const Text('فتح جلسة')),
          OutlinedButton.icon(onPressed: _busy || session == null ? null : _closeSession, icon: const Icon(Icons.lock_clock), label: const Text('إقفال الصندوق')),
        ]),
      ]))),
      const SizedBox(height: 12),
      Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text('حركات الصندوق ${_transactions.length}', style: Theme.of(context).textTheme.titleMedium)), SizedBox(width: 260, child: TextField(controller: _search, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'بحث في الحركات'), onChanged: (v) => setState(() => _filter = v.trim()))) ]),
        const SizedBox(height: 8),
        if (_transactions.isEmpty) const Text('لا توجد حركات مسجلة لهذا الصندوق.')
        else SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(columns: const [
          DataColumn(label: Text('التاريخ')), DataColumn(label: Text('نوع الحركة')), DataColumn(label: Text('الداخل / الخارج')), DataColumn(label: Text('المرجع')), DataColumn(label: Text('ملاحظات')),
        ], rows: _transactions.where((r) => _filter.isEmpty || r.values.any((v) => v.toString().toLowerCase().contains(_filter.toLowerCase()))).map((r) => DataRow(cells: [
          DataCell(Text((r['transaction_date'] ?? '—').toString())),
          DataCell(Text((r['type'] ?? '—').toString())),
          DataCell(Text(_money(r['amount']), style: TextStyle(color: ((r['amount'] as num?)?.toDouble() ?? 0) < 0 ? Colors.red : Colors.green))),
          DataCell(Text((r['reference'] ?? '—').toString())),
          DataCell(Text((r['notes'] ?? '—').toString())),
        ])).toList())),
      ]))),
      const SizedBox(height: 12),
      Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('سجل جلسات الصناديق (${_sessions.length})', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_sessions.isEmpty) const Text('لا توجد جلسات سابقة.')
        else SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(columns: const [
          DataColumn(label: Text('رقم الجلسة')), DataColumn(label: Text('الصندوق')), DataColumn(label: Text('وقت الفتح')), DataColumn(label: Text('وقت الإقفال')), DataColumn(label: Text('النظامي')), DataColumn(label: Text('الفعلي')), DataColumn(label: Text('الفرق')), DataColumn(label: Text('الحالة')),
        ], rows: _sessions.map((s) {
          final name = _boxes.where((b) => (b['id'] as num).toInt() == (s['cash_box_id'] as num?)?.toInt()).map((b) => (b['name'] ?? '').toString()).firstWhere((v) => true, orElse: () => '—');
          return DataRow(cells: [
            DataCell(Text((s['session_no'] ?? '—').toString())),
            DataCell(Text(name)),
            DataCell(Text((s['opened_at'] ?? '—').toString())),
            DataCell(Text((s['closed_at'] ?? '—').toString())),
            DataCell(Text(_money(s['expected_balance']))),
            DataCell(Text(_money(s['actual_balance']))),
            DataCell(Text(_money(s['difference']))),
            DataCell(Text((s['status'] ?? '—').toString())),
          ]);
        }).toList())),
      ]))),
      const SizedBox(height: 12),
      Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('قائمة الصناديق (${visibleBoxes.length})', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'بحث باسم الصندوق'), onChanged: (v) => setState(() => _filter = v.trim())),
        const SizedBox(height: 8),
        if (visibleBoxes.isEmpty) const Text('لا توجد صناديق.')
        else SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(columns: const [
          DataColumn(label: Text('الاسم')), DataColumn(label: Text('الرصيد الحالي')), DataColumn(label: Text('الحالة')), DataColumn(label: Text('إجراء')),
        ], rows: visibleBoxes.map((b) => DataRow(selected: b['id'] == _boxId, onSelectChanged: (_) => setState(() { _boxId = (b['id'] as num).toInt(); _name.text = (b['name'] ?? '').toString(); _active = ((b['is_active'] as num?)?.toInt() ?? 1) == 1; }), cells: [
          DataCell(Text((b['name'] ?? '—').toString())),
          DataCell(Text(_money(b['balance']))),
          DataCell(Text(((b['is_active'] as num?)?.toInt() ?? 0) == 1 ? 'نشط' : 'غير نشط')),
          DataCell(IconButton(tooltip: 'تحديد الصندوق', onPressed: () => setState(() { _boxId = (b['id'] as num).toInt(); _name.text = (b['name'] ?? '').toString(); _active = ((b['is_active'] as num?)?.toInt() ?? 1) == 1; }), icon: const Icon(Icons.edit_outlined))),
        ])).toList())),
      ]))),
    ]);
  }
}
