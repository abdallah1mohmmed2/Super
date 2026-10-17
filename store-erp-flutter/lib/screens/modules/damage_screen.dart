import 'package:flutter/material.dart';
import '../../data/database_helper.dart';

class DamageDocumentsScreen extends StatefulWidget {
  const DamageDocumentsScreen({super.key});
  @override
  State<DamageDocumentsScreen> createState() => _DamageDocumentsScreenState();
}

class _DamageDocumentsScreenState extends State<DamageDocumentsScreen> {
  final db = DatabaseHelper.instance;
  final _number = TextEditingController();
  final _cause = TextEditingController();
  final _productSearch = TextEditingController();
  final _qty = TextEditingController(text: '1');
  final _batch = TextEditingController();
  final _cost = TextEditingController(text: '0');
  List<Map<String, Object?>> warehouses = [], products = [], docs = [], lines = [], batches = [];
  int? warehouseId, productId, selectedLineId, documentId, batchId;
  DateTime date = DateTime.now();
  String documentType = 'تالف', status = 'مسودة', reason = 'تالف';
  bool busy = false;
  String get dateText => date.toIso8601String().substring(0, 10);
  double n(Object? v) => (v as num?)?.toDouble() ?? 0;
  void msg(String s) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s))); }

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _number.dispose(); _cause.dispose(); _productSearch.dispose(); _qty.dispose(); _batch.dispose(); _cost.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final w = await db.query('warehouses', where: 'is_active=1', orderBy: 'name');
      final p = await db.query('products', where: 'is_active=1', orderBy: 'name');
      final d = await db.query('damage_documents', orderBy: 'document_date DESC', limit: 300);
      if (!mounted) return;
      setState(() { warehouses = w; products = p; docs = d; warehouseId ??= w.isEmpty ? null : (w.first['id'] as num).toInt(); });
      await _loadBatches();
    } catch (e) { msg('تعذر تحميل سندات التالف: $e'); }
  }

  Future<void> _loadBatches() async {
    if (productId == null || warehouseId == null) { if (mounted) setState(() => batches = []); return; }
    final rows = await db.query('product_batches', where: 'product_id=? AND warehouse_id=? AND qty>0', whereArgs: [productId, warehouseId], orderBy: 'expiry_date');
    if (mounted) setState(() { batches = rows; batchId = rows.isEmpty ? null : (rows.first['id'] as num).toInt(); });
  }

  Future<void> _newDoc() async {
    if (warehouseId == null) { msg('أضف مخزنًا نشطًا أولًا'); return; }
    final id = await db.insert('damage_documents', {
      'document_no': 'DMG-${DateTime.now().microsecondsSinceEpoch}',
      'document_date': dateText, 'warehouse_id': warehouseId, 'document_type': documentType,
      'cause': _cause.text.trim().isEmpty ? reason : _cause.text.trim(), 'status': 'مسودة',
    });
    if (!mounted) return;
    setState(() { documentId = id; _number.text = 'DMG-$id'; status = 'مسودة'; lines = []; selectedLineId = null; });
    await _reloadDocs();
    msg('تم إنشاء سند جديد');
  }

  Future<void> _reloadDocs() async {
    final rows = await db.query('damage_documents', orderBy: 'document_date DESC', limit: 300);
    if (mounted) setState(() => docs = rows);
  }

  Future<void> _openDoc(Map<String, Object?> doc) async {
    final id = (doc['id'] as num).toInt();
    final rows = await db.query('damage_lines', where: 'document_id=?', whereArgs: [id], orderBy: 'id');
    if (!mounted) return;
    setState(() {
      documentId = id; _number.text = (doc['document_no'] ?? '').toString();
      date = DateTime.tryParse((doc['document_date'] ?? '').toString()) ?? DateTime.now();
      warehouseId = (doc['warehouse_id'] as num?)?.toInt();
      documentType = (doc['document_type'] ?? 'تالف').toString();
      _cause.text = (doc['cause'] ?? '').toString();
      status = (doc['status'] ?? 'مسودة').toString();
      lines = rows.map((r) => Map<String, Object?>.from(r)).toList(); selectedLineId = null;
    });
  }

  Future<void> _addLine() async {
    if (documentId == null) { msg('أنشئ سندًا أولًا'); return; }
    if (status != 'مسودة') { msg('لا يمكن تعديل سند غير مسودة'); return; }
    if (productId == null) { msg('اختر الصنف'); return; }
    final qty = double.tryParse(_qty.text) ?? 0;
    final cost = double.tryParse(_cost.text) ?? 0;
    if (qty <= 0 || cost < 0) { msg('أدخل كمية موجبة وتكلفة غير سالبة'); return; }
    final existing = lines.where((r) => (r['product_id'] as num).toInt() == productId && (r['batch_no'] ?? '') == _batch.text).toList();
    if (existing.isNotEmpty) {
      final row = existing.first;
      final nextQty = n(row['qty']) + qty;
      await db.update('damage_lines', {'qty': nextQty, 'estimated_cost': cost}, where: 'id=?', whereArgs: [row['id']]);
    } else {
      await db.insert('damage_lines', {
        'document_id': documentId, 'product_id': productId, 'qty': qty,
        'estimated_cost': cost, 'batch_no': _batch.text.trim().isEmpty ? null : _batch.text.trim(),
      });
    }
    final rows = await db.query('damage_lines', where: 'document_id=?', whereArgs: [documentId], orderBy: 'id');
    if (mounted) setState(() { lines = rows; _qty.text = '1'; selectedLineId = null; });
  }

  Future<void> _deleteLine() async {
    if (selectedLineId == null || status != 'مسودة') { msg('حدد سطرًا من سند مسودة'); return; }
    await db.delete('damage_lines', where: 'id=? AND document_id=?', whereArgs: [selectedLineId, documentId]);
    if (mounted) setState(() { lines.removeWhere((r) => r['id'] == selectedLineId); selectedLineId = null; });
  }

  Future<void> _save() async {
    if (documentId == null) { msg('أنشئ سندًا أولًا'); return; }
    if (status != 'مسودة') { msg('لا يمكن تعديل سند غير مسودة'); return; }
    try {
      await db.update('damage_documents', {
        'document_no': _number.text.trim(), 'document_date': dateText, 'warehouse_id': warehouseId,
        'document_type': documentType, 'cause': _cause.text.trim(),
      }, where: 'id=?', whereArgs: [documentId]);
      await _reloadDocs(); msg('تم حفظ السند');
    } catch (e) { msg('تعذر حفظ السند: $e'); }
  }

  Future<void> _post() async {
    if (documentId == null || lines.isEmpty) { msg('أنشئ السند وأضف الأصناف أولًا'); return; }
    if (status != 'مسودة') { msg('السند غير قابل للترحيل بهذه الحالة'); return; }
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('تأكيد ترحيل سند التالف/المنتهي'),
      content: const Text('سيتم خصم الكميات من المخزون وإنشاء القيد المحاسبي.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ترحيل'))],
    ));
    if (ok != true || !mounted) return;
    setState(() => busy = true);
    try {
      await _save();
      await db.postDamage(documentId: documentId!, lines: lines.map((r) => <String, num>{
        'product_id': (r['product_id'] as num), 'qty': n(r['qty']),
      }).toList());
      if (mounted) setState(() => status = 'مرحل');
      await _reloadDocs(); msg('تم ترحيل السند وتحديث المخزون والحسابات');
    } catch (e) { msg('تعذر ترحيل السند: $e'); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> _pickDate() async {
    final value = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (value != null && mounted) setState(() => date = value);
  }

  @override
  Widget build(BuildContext context) {
    final q = _productSearch.text.trim().toLowerCase();
    final matches = products.where((p) => q.isEmpty || (p['name'] ?? '').toString().toLowerCase().contains(q) || (p['code'] ?? '').toString().toLowerCase().contains(q)).take(50).toList();
    final total = lines.fold<double>(0, (sum, r) => sum + n(r['qty']) * n(r['estimated_cost']));
    return ListView(padding: const EdgeInsets.all(18), children: [
      Row(children: [const Expanded(child: Text('سند التالف والمنتهي', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold))), Chip(label: Text(status))]),
      Card(child: Padding(padding: const EdgeInsets.all(14), child: Wrap(spacing: 12, runSpacing: 12, children: [
        SizedBox(width: 200, child: TextField(controller: _number, decoration: const InputDecoration(labelText: 'رقم المستند', border: OutlineInputBorder()))),
        SizedBox(width: 200, child: DropdownButtonFormField<String>(value: documentType, decoration: const InputDecoration(labelText: 'نوع المستند', border: OutlineInputBorder()), items: const ['تالف','منتهي الصلاحية'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: status == 'مسودة' ? (v) => setState(() => documentType = v ?? 'تالف') : null)),
        SizedBox(width: 220, child: DropdownButtonFormField<int>(value: warehouses.any((w) => (w['id'] as num).toInt() == warehouseId) ? warehouseId : null, decoration: const InputDecoration(labelText: 'المخزن', border: OutlineInputBorder()), items: warehouses.map((w) => DropdownMenuItem(value: (w['id'] as num).toInt(), child: Text((w['name'] ?? '').toString()))).toList(), onChanged: status == 'مسودة' ? (v) { setState(() => warehouseId = v); _loadBatches(); } : null)),
        OutlinedButton.icon(onPressed: _pickDate, icon: const Icon(Icons.calendar_month), label: Text(dateText)),
        SizedBox(width: 240, child: TextField(controller: _cause, decoration: const InputDecoration(labelText: 'سبب التلف/الانتهاء', border: OutlineInputBorder()))),
        OutlinedButton.icon(onPressed: _newDoc, icon: const Icon(Icons.add), label: const Text('جديد')),
        OutlinedButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: const Text('حفظ')),
        OutlinedButton.icon(onPressed: () async { final doc = await showDialog<Map<String,Object?>>(context: context, builder: (ctx) => SimpleDialog(title: const Text('تحميل مستند'), children: docs.map((d) => SimpleDialogOption(onPressed: () => Navigator.pop(ctx,d), child: Text('${d['document_no']} • ${d['status']} • ${d['document_date']}'))).toList()); if (doc != null) await _openDoc(doc); }, icon: const Icon(Icons.folder_open), label: const Text('تحميل مستند')),
      ]))),
      Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('إدخال الصنف', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        TextField(controller: _productSearch, decoration: const InputDecoration(labelText: 'بحث بالاسم أو الكود', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()), onChanged: (_) => setState(() {})),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 12, children: [
          SizedBox(width: 300, child: DropdownButtonFormField<int>(value: products.any((p) => (p['id'] as num).toInt() == productId) ? productId : null, decoration: const InputDecoration(labelText: 'الصنف المختار', border: OutlineInputBorder()), items: matches.map((p) => DropdownMenuItem(value: (p['id'] as num).toInt(), child: Text('${p['name']} • ${p['code'] ?? ''}', overflow: TextOverflow.ellipsis))).toList(), onChanged: status == 'مسودة' ? (v) { setState(() { productId = v; final p = products.firstWhere((p) => (p['id'] as num).toInt() == v); _cost.text = n(p['cost_price']).toStringAsFixed(2); }); _loadBatches(); } : null)),
          SizedBox(width: 140, child: TextField(controller: _qty, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'الكمية الأساسية', border: OutlineInputBorder()))),
          SizedBox(width: 150, child: TextField(controller: _cost, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'تكلفة الوحدة', border: OutlineInputBorder()))),
          SizedBox(width: 220, child: DropdownButtonFormField<int?>(value: batchId, decoration: const InputDecoration(labelText: 'رقم الدفعة', border: OutlineInputBorder()), items: [const DropdownMenuItem<int?>(value: null, child: Text('بدون دفعة')), ...batches.map((b) => DropdownMenuItem<int?>(value: (b['id'] as num).toInt(), child: Text('${b['batch_no'] ?? b['id']} • رصيد ${b['qty']}'))], onChanged: (v) { setState(() { batchId = v; final b = batches.where((b) => (b['id'] as num).toInt() == v).firstOrNull; _batch.text = (b?['batch_no'] ?? '').toString(); }); })),
          FilledButton.icon(onPressed: busy ? null : _addLine, icon: const Icon(Icons.add), label: const Text('إضافة سطر')),
          OutlinedButton.icon(onPressed: busy ? null : _deleteLine, icon: const Icon(Icons.delete_outline), label: const Text('حذف السطر')),
        ]),
      ]))),
      Card(child: Padding(padding: const EdgeInsets.all(10), child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(columns: const [
        DataColumn(label: Text('تحديد')), DataColumn(label: Text('الصنف')), DataColumn(label: Text('الكمية')), DataColumn(label: Text('تكلفة الوحدة')), DataColumn(label: Text('رقم الدفعة')), DataColumn(label: Text('الإجمالي')),
      ], rows: lines.map((r) {
        final p = products.where((p) => (p['id'] as num).toInt() == (r['product_id'] as num).toInt()).firstOrNull;
        final selected = selectedLineId == (r['id'] as num).toInt();
        return DataRow(selected: selected, onSelectChanged: (_) => setState(() => selectedLineId = (r['id'] as num).toInt()), cells: [
          DataCell(Checkbox(value: selected, onChanged: (_) => setState(() => selectedLineId = (r['id'] as num).toInt()))),
          DataCell(Text((p?['name'] ?? r['product_id']).toString())),
          DataCell(Text(n(r['qty']).toStringAsFixed(2))),
          DataCell(Text(n(r['estimated_cost']).toStringAsFixed(2))),
          DataCell(Text((r['batch_no'] ?? '—').toString())),
          DataCell(Text((n(r['qty']) * n(r['estimated_cost'])).toStringAsFixed(2))),
        ]);
      }).toList()))),
      Card(child: Padding(padding: const EdgeInsets.all(14), child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('عدد السطور: ${lines.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
        Text('إجمالي التكلفة التقديرية: ${total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
        FilledButton.icon(onPressed: busy ? null : _post, icon: const Icon(Icons.publish), label: const Text('حفظ وترحيل')),
        OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('تحديث')),
        OutlinedButton.icon(onPressed: () => Navigator.maybePop(context), icon: const Icon(Icons.close), label: const Text('إغلاق')),
      ]))),
      if (busy) const LinearProgressIndicator(),
    ]);
  }
}
