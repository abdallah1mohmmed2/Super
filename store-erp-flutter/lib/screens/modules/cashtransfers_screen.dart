import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database_helper.dart';
import '../../providers/app_provider.dart';

class CashTransfersScreen extends StatefulWidget {
  const CashTransfersScreen({super.key});

  @override
  State<CashTransfersScreen> createState() => _CashTransfersScreenState();
}

class _CashTransfersScreenState extends State<CashTransfersScreen> {
  final _db = DatabaseHelper.instance;
  final _number = TextEditingController();
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  List<Map<String, Object?>> _boxes = [];
  List<Map<String, Object?>> _transfers = [];
  int? _selectedId;
  int? _fromId;
  int? _toId;
  DateTime _date = DateTime.now();
  bool _busy = false;
  String _status = 'مسودة';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _number.dispose();
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _message(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  String _dateText(DateTime value) => value.toIso8601String().substring(0, 10);
  double _balance(Map<String, Object?>? row) => (row?['balance'] as num?)?.toDouble() ?? 0;
  Map<String, Object?>? _box(int? id) {
    for (final row in _boxes) {
      if ((row['id'] as num?)?.toInt() == id) return row;
    }
    return null;
  }

  int? _firstOtherBoxId(int? exceptId) {
    for (final row in _boxes) {
      final id = (row['id'] as num).toInt();
      if (id != exceptId) return id;
    }
    return null;
  }

  Future<void> _reload() async {
    try {
      final boxes = await _db.query('cash_boxes', where: 'is_active=1', orderBy: 'name');
      final transfers = await _db.query('cash_transfers', orderBy: 'id DESC');
      if (!mounted) return;
      setState(() {
        _boxes = boxes;
        _transfers = transfers;
        if (_fromId == null || !_boxes.any((b) => (b['id'] as num).toInt() == _fromId)) {
          _fromId = _boxes.isEmpty ? null : (_boxes.first['id'] as num).toInt();
        }
        if (_toId == null || !_boxes.any((b) => (b['id'] as num).toInt() == _toId) || _toId == _fromId) {
          _toId = _firstOtherBoxId(_fromId);
        }
      });
    } catch (e) {
      _message('تعذر تحميل الصناديق والتحويلات: $e');
    }
  }

  void _newTransfer() {
    setState(() {
      _selectedId = null;
      _number.clear();
      _amount.clear();
      _reason.clear();
      _date = DateTime.now();
      _status = 'مسودة';
      _fromId = _boxes.isEmpty ? null : (_boxes.first['id'] as num).toInt();
      _toId = _boxes.where((b) => (b['id'] as num).toInt() != _fromId).map((b) => (b['id'] as num).toInt()).firstOrNull;
    });
  }

  void _select(Map<String, Object?> row) {
    if (row['status'] == 'مرحل') {
      setState(() {
        _selectedId = (row['id'] as num).toInt();
        _number.text = (row['transfer_no'] ?? '').toString();
        _amount.text = ((row['amount'] as num?)?.toString() ?? '');
        _reason.text = (row['reason'] ?? '').toString();
        _fromId = (row['from_cashbox_id'] as num?)?.toInt();
        _toId = (row['to_cashbox_id'] as num?)?.toInt();
        _date = DateTime.tryParse((row['transfer_date'] ?? '').toString()) ?? DateTime.now();
        _status = 'مرحل';
      });
      return;
    }
    setState(() {
      _selectedId = (row['id'] as num).toInt();
      _number.text = (row['transfer_no'] ?? '').toString();
      _amount.text = ((row['amount'] as num?)?.toString() ?? '');
      _reason.text = (row['reason'] ?? '').toString();
      _fromId = (row['from_cashbox_id'] as num?)?.toInt();
      _toId = (row['to_cashbox_id'] as num?)?.toInt();
      _date = DateTime.tryParse((row['transfer_date'] ?? '').toString()) ?? DateTime.now();
      _status = (row['status'] ?? 'مسودة').toString();
    });
  }

  Future<int?> _persistDraft() async {
    if (_fromId == null || _toId == null) throw StateError('اختر الصندوق المصدر والصندوق المستلم');
    if (_fromId == _toId) throw StateError('يجب اختيار صندوقين مختلفين');
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) throw StateError('أدخل مبلغ تحويل أكبر من صفر');
    if (_number.text.trim().isEmpty) _number.text = 'CT-${DateTime.now().millisecondsSinceEpoch}';
    final data = <String, Object?>{
      'transfer_no': _number.text.trim(),
      'from_cashbox_id': _fromId,
      'to_cashbox_id': _toId,
      'amount': amount,
      'reason': _reason.text.trim(),
      'transfer_date': _dateText(_date),
      'status': 'مسودة',
    };
    if (_selectedId == null) {
      _selectedId = await _db.insert('cash_transfers', data);
    } else {
      final old = await _db.query('cash_transfers', where: 'id=?', whereArgs: [_selectedId], limit: 1);
      if (old.isNotEmpty && old.first['status'] == 'مرحل') throw StateError('لا يمكن تعديل تحويل مرحل');
      await _db.update('cash_transfers', data, where: 'id=?', whereArgs: [_selectedId]);
    }
    return _selectedId;
  }

  Future<void> _saveDraft() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _persistDraft();
      await _reload();
      if (mounted) _message('تم حفظ مسودة التحويل');
    } catch (e) {
      _message('تعذر حفظ المسودة: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _post() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final id = await _persistDraft();
      if (id == null) throw StateError('تعذر إنشاء مستند التحويل');
      await _db.transferCash(transferId: id);
      await context.read<AppProvider>().refresh();
      await _reload();
      if (mounted) _message('تم ترحيل التحويل وتحديث رصيدي الصندوقين');
    } catch (e) {
      _message('تعذر ترحيل التحويل: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _balanceCard(String title, int? id) {
    final box = _box(id);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 5),
          Text(box == null ? '—' : (box['name'] ?? 'صندوق').toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(_balance(box).toStringAsFixed(2), style: Theme.of(context).textTheme.titleLarge),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPosted = _status == 'مرحل';
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Row(children: [
          const Expanded(child: Text('تحويل الصناديق', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
          OutlinedButton.icon(onPressed: _busy ? null : _reload, icon: const Icon(Icons.refresh), label: const Text('تحديث سجل التحويلات')),
          const SizedBox(width: 8),
          FilledButton.icon(onPressed: _busy ? null : _newTransfer, icon: const Icon(Icons.add), label: const Text('جديد')),
        ]),
        const SizedBox(height: 12),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_selectedId == null ? 'بيانات التحويل الجديد' : 'تحويل رقم $_selectedId — $_status', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 12, children: [
            SizedBox(width: 260, child: TextField(controller: _number, decoration: const InputDecoration(labelText: 'رقم التحويل', prefixIcon: Icon(Icons.numbers)))),
            SizedBox(width: 260, child: DropdownButtonFormField<int>(value: _boxes.any((b) => (b['id'] as num).toInt() == _fromId) ? _fromId : null, decoration: const InputDecoration(labelText: 'من صندوق'), items: _boxes.map((b) => DropdownMenuItem(value: (b['id'] as num).toInt(), child: Text((b['name'] ?? '').toString()))).toList(), onChanged: isPosted ? null : (v) => setState(() { _fromId = v; if (_toId == v) _toId = _firstOtherBoxId(v); }))),
            SizedBox(width: 260, child: DropdownButtonFormField<int>(value: _boxes.any((b) => (b['id'] as num).toInt() == _toId) ? _toId : null, decoration: const InputDecoration(labelText: 'إلى صندوق'), items: _boxes.where((b) => (b['id'] as num).toInt() != _fromId).map((b) => DropdownMenuItem(value: (b['id'] as num).toInt(), child: Text((b['name'] ?? '').toString()))).toList(), onChanged: isPosted ? null : (v) => setState(() => _toId = v))),
            SizedBox(width: 220, child: OutlinedButton.icon(onPressed: isPosted || _busy ? null : () async { final picked = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2000), lastDate: DateTime(2100)); if (picked != null && mounted) setState(() => _date = picked); }, icon: const Icon(Icons.calendar_month), label: Text('التاريخ: ${_dateText(_date)}'))),
            SizedBox(width: 220, child: TextField(controller: _amount, readOnly: isPosted, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'المبلغ', prefixIcon: Icon(Icons.payments_outlined)))),
            SizedBox(width: 380, child: TextField(controller: _reason, readOnly: isPosted, decoration: const InputDecoration(labelText: 'السبب / الملاحظات', prefixIcon: Icon(Icons.notes)))),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 12, children: [
            SizedBox(width: 240, child: _balanceCard('الرصيد الحالي — المرسل', _fromId)),
            SizedBox(width: 240, child: _balanceCard('الرصيد الحالي — المستقبل', _toId)),
          ]),
          const SizedBox(height: 14),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(onPressed: _busy || isPosted ? null : _saveDraft, icon: const Icon(Icons.save_outlined), label: const Text('حفظ مسودة')),
            FilledButton.icon(onPressed: _busy || isPosted ? null : _post, icon: const Icon(Icons.verified_outlined), label: Text(_busy ? 'جارٍ التنفيذ...' : 'حفظ وترحيل')),
            OutlinedButton.icon(onPressed: _busy ? null : _newTransfer, icon: const Icon(Icons.cleaning_services_outlined), label: const Text('تفريغ')),
          ]),
          if (_boxes.length < 2) const Padding(padding: EdgeInsets.only(top: 10), child: Text('يلزم إنشاء صندوقين نشطين على الأقل لإجراء تحويل.', style: TextStyle(color: Colors.deepOrange))),
        ]))),
        const SizedBox(height: 14),
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('سجل التحويلات السابقة (${_transfers.length})', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_transfers.isEmpty) const Text('لا توجد تحويلات مسجلة.')
          else SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(columns: const [
            DataColumn(label: Text('رقم التحويل')), DataColumn(label: Text('التاريخ')), DataColumn(label: Text('من صندوق')), DataColumn(label: Text('إلى صندوق')), DataColumn(label: Text('المبلغ')), DataColumn(label: Text('الحالة')), DataColumn(label: Text('إجراء')),
          ], rows: _transfers.map((row) {
            String boxName(Object? id) => _box((id as num?)?.toInt())?['name']?.toString() ?? '—';
            return DataRow(selected: row['id'] == _selectedId, onSelectChanged: (_) => _select(row), cells: [
              DataCell(Text((row['transfer_no'] ?? '—').toString())),
              DataCell(Text((row['transfer_date'] ?? '—').toString())),
              DataCell(Text(boxName(row['from_cashbox_id']))),
              DataCell(Text(boxName(row['to_cashbox_id']))),
              DataCell(Text(((row['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2))),
              DataCell(Text((row['status'] ?? 'مسودة').toString())),
              DataCell(IconButton(tooltip: 'فتح التحويل', onPressed: () => _select(row), icon: const Icon(Icons.open_in_new))),
            ]);
          }).toList())),
        ]))),
      ],
    );
  }
}
