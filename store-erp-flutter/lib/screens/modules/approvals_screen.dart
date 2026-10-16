import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database_helper.dart';
import '../../providers/app_provider.dart';

class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key});
  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  final _db = DatabaseHelper.instance;
  final _decisionNotes = TextEditingController();
  List<Map<String,Object?>> _pending = [];
  List<Map<String,Object?>> _history = [];
  int? _selectedId;
  bool _busy = false;

  @override
  void initState() { super.initState(); _reload(); }
  @override
  void dispose() { _decisionNotes.dispose(); super.dispose(); }

  void _message(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _reload() async {
    try {
      final pending = await _db.query('approval_requests', where: 'status=?', whereArgs: ['معلق'], orderBy: 'request_date DESC');
      final history = await _db.query('approval_requests', where: 'status!=?', whereArgs: ['معلق'], orderBy: 'decided_at DESC', limit: 100);
      if (!mounted) return;
      setState(() {
        _pending = pending;
        _history = history;
        if (_selectedId == null || !_pending.any((r) => (r['id'] as num).toInt() == _selectedId)) {
          _selectedId = _pending.isEmpty ? null : (_pending.first['id'] as num).toInt();
          _decisionNotes.clear();
        }
      });
    } catch (e) {
      _message('تعذر تحميل طلبات الاعتماد: $e');
    }
  }

  Map<String,Object?>? get _selected {
    for (final row in _pending) {
      if ((row['id'] as num).toInt() == _selectedId) return row;
    }
    return null;
  }

  Future<void> _decide(bool approve) async {
    final row = _selected;
    if (row == null) { _message('حدد طلبًا معلقًا أولًا'); return; }
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(approve ? 'تأكيد الاعتماد' : 'تأكيد رفض الطلب'),
      content: Text(approve ? 'هل تريد اعتماد الطلب ${row['reference'] ?? row['entity_id']}؟' : 'هل تريد رفض الطلب ${row['reference'] ?? row['entity_id']}؟'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(approve ? 'اعتماد' : 'رفض')),
      ],
    ));
    if (yes != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _db.update('approval_requests', {
        'status': approve ? 'معتمد' : 'مرفوض',
        'decision_notes': _decisionNotes.text.trim(),
        'decided_by': context.read<AppProvider>().currentUser,
        'decided_at': DateTime.now().toIso8601String(),
      }, where: 'id=? AND status=?', whereArgs: [row['id'], 'معلق']);
      await _db.insert('audit_log', {
        'action': approve ? 'اعتماد طلب' : 'رفض طلب',
        'entity': 'approval_requests',
        'entity_id': row['id'],
        'details': 'المرجع: ${row['reference'] ?? row['entity_id']}؛ ${_decisionNotes.text.trim()}',
      });
      _decisionNotes.clear();
      await _reload();
      if (mounted) _message(approve ? 'تم اعتماد الطلب' : 'تم رفض الطلب');
    } catch (e) {
      _message('تعذر حفظ قرار الاعتماد: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _detail(String title, Object? value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 125, child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
      Expanded(child: SelectableText((value == null || value.toString().isEmpty) ? '—' : value.toString())),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final row = _selected;
    return ListView(padding: const EdgeInsets.all(18), children: [
      Row(children: [
        const Expanded(child: Text('اعتمادات المدير', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
        OutlinedButton.icon(onPressed: _busy ? null : _reload, icon: const Icon(Icons.refresh), label: const Text('تحديث')),
      ]),
      const SizedBox(height: 12),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 6, child: Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('الطلبات المعلقة (${_pending.length})', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_pending.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('لا توجد طلبات معلقة حاليًا.')))
          else SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(columns: const [
            DataColumn(label: Text('نوع الطلب')), DataColumn(label: Text('المرجع')), DataColumn(label: Text('مقدم الطلب')), DataColumn(label: Text('تاريخ الطلب')),
          ], rows: _pending.map((r) => DataRow(selected: r['id'] == _selectedId, onSelectChanged: (_) => setState(() { _selectedId = (r['id'] as num).toInt(); _decisionNotes.text = (r['decision_notes'] ?? '').toString(); }), cells: [
            DataCell(Text((r['request_type'] ?? '—').toString())),
            DataCell(Text((r['reference'] ?? r['entity_id'] ?? '—').toString())),
            DataCell(Text((r['requested_by'] ?? '—').toString())),
            DataCell(Text((r['request_date'] ?? '—').toString())),
          ])).toList()),
        ])))),
        const SizedBox(width: 12),
        Expanded(flex: 5, child: Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('تفاصيل الطلب والقرار', style: Theme.of(context).textTheme.titleMedium),
          const Divider(),
          if (row == null) const Padding(padding: EdgeInsets.all(18), child: Text('اختر طلبًا من الجدول لعرض التفاصيل.'))
          else ...[
            _detail('نوع الطلب', row['request_type']),
            _detail('المرجع', row['reference']),
            _detail('معرّف السجل', row['entity_id']),
            _detail('مقدم الطلب', row['requested_by']),
            _detail('تاريخ الطلب', row['request_date']),
            _detail('ملاحظات الطلب', row['request_notes']),
            const SizedBox(height: 10),
            TextField(controller: _decisionNotes, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'ملاحظات القرار', alignLabelWithHint: true, border: OutlineInputBorder())),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(onPressed: _busy ? null : () => _decide(true), icon: const Icon(Icons.check_circle_outline), label: const Text('اعتماد')),
              FilledButton.tonalIcon(onPressed: _busy ? null : () => _decide(false), icon: const Icon(Icons.cancel_outlined), label: const Text('رفض')),
            ]),
          ],
        ])))),
      ]),
      const SizedBox(height: 12),
      Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('سجل القرارات السابقة (${_history.length})', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_history.isEmpty) const Text('لا توجد قرارات سابقة.')
        else SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(columns: const [
          DataColumn(label: Text('نوع الطلب')), DataColumn(label: Text('المرجع')), DataColumn(label: Text('القرار')), DataColumn(label: Text('صاحب القرار')), DataColumn(label: Text('التاريخ')), DataColumn(label: Text('ملاحظات القرار')),
        ], rows: _history.map((r) => DataRow(cells: [
          DataCell(Text((r['request_type'] ?? '—').toString())),
          DataCell(Text((r['reference'] ?? r['entity_id'] ?? '—').toString())),
          DataCell(Text((r['status'] ?? '—').toString())),
          DataCell(Text((r['decided_by'] ?? '—').toString())),
          DataCell(Text((r['decided_at'] ?? '—').toString())),
          DataCell(Text((r['decision_notes'] ?? '—').toString())),
        ])).toList())),
      ]))),
    ]);
  }
}
