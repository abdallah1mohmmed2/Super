import 'package:flutter/material.dart';
import '../../widgets/common_widgets.dart';
import 'package:provider/provider.dart';
import '../../data/database_helper.dart';
import '../../providers/app_provider.dart';

class InventoryCountScreen extends StatefulWidget {
  final String countType;
  final int? initialDocumentId;
  const InventoryCountScreen({super.key, required this.countType, this.initialDocumentId});
  @override
  State<InventoryCountScreen> createState() => _InventoryCountScreenState();
}

class _InventoryCountScreenState extends State<InventoryCountScreen> {
  final db = DatabaseHelper.instance;
  final search = TextEditingController();
  final notes = TextEditingController();
  final number = TextEditingController();
  final limit = TextEditingController(text: '500');
  List<Map<String, Object?>> warehouses = [], products = [], documents = [], items = [], categories = [], users = [], barcodes = [];
  int? warehouseId, categoryId, documentId, selectedItemId;
  DateTime inventoryDate = DateTime.now();
  int selectedMonth = DateTime.now().month, selectedYear = DateTime.now().year;
  bool includeZero = false, busy = false;
  String status = 'مسودة';
  String get typeLabel => switch (widget.countType) {
    'dailycount' => 'الجرد اليومي',
    'monthlycount' => 'الجرد الشهري',
    'yearlycount' => 'الجرد السنوي',
    _ => 'الجرد الفعلي',
  };
  String get typeCode => switch (widget.countType) {
    'dailycount' => 'يومي',
    'monthlycount' => 'شهري',
    'yearlycount' => 'سنوي',
    _ => 'فعلي',
  };
  double n(Object? v) => (v as num?)?.toDouble() ?? 0;
  String dateText(DateTime d) => d.toIso8601String().substring(0, 10);
  void msg(String s) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s))); }

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { search.dispose(); notes.dispose(); number.dispose(); limit.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => busy = true);
    try {
      final w = await db.query('warehouses', where: 'is_active=1', orderBy: 'name');
      final p = await db.query('products', where: 'is_active=1', orderBy: 'name');
      final c = await db.query('categories', orderBy: 'name');
      final b = await db.query('barcodes', orderBy: 'barcode');
      final d = await db.query('inventory_documents', where: 'inventory_type=?', whereArgs: [typeCode], orderBy: 'inventory_date DESC', limit: 300);
      final u = await db.query('users', orderBy: 'full_name');
      if (!mounted) return;
      setState(() {
        warehouses = w; products = p; categories = c; documents = d; users = u; barcodes = b;
        warehouseId ??= w.isEmpty ? null : (w.first['id'] as num).toInt();
      });
    } catch (e) { msg('تعذر تحميل بيانات الجرد: $e'); }
    finally { if (mounted) setState(() => busy = false); }
    if (widget.initialDocumentId != null && documentId == null) {
      final matches = documents.where((d) => (d['id'] as num).toInt() == widget.initialDocumentId);
      if (matches.isNotEmpty) await _openDocument(matches.first);
    }
  }

  Future<int?> _currentUserId() async {
    final current = context.read<AppProvider>().currentUser.trim();
    final rows = await db.query('users');
    final match = rows.where((u) => (u['username'] ?? '').toString() == current || (u['full_name'] ?? '').toString() == current).firstOrNull;
    return (match?['id'] as num?)?.toInt();
  }

  String _userName(Object? id) {
    if (id == null) return '—';
    final user = users.where((u) => (u['id'] as num?)?.toInt() == (id as num?)?.toInt()).firstOrNull;
    return user == null ? '—' : (user['full_name'] ?? user['username'] ?? '—').toString();
  }

  Future<void> _newDocument() async {
    if (warehouseId == null) { msg('أضف مخزنًا نشطًا أولًا'); return; }
    final creatorId = await _currentUserId();
    final id = await db.insert('inventory_documents', {
      'created_by': creatorId,
      'document_no': 'CNT-${DateTime.now().microsecondsSinceEpoch}',
      'inventory_date': dateText(inventoryDate),
      'warehouse_id': warehouseId,
      'inventory_type': typeCode,
      'status': 'مسودة',
    });
    if (!mounted) return;
    setState(() {
      documentId = id; number.text = 'CNT-$id'; status = 'مسودة'; items = [];
      notes.clear(); selectedItemId = null;
    });
    await _loadDocuments();
    msg('تم إنشاء مستند الجرد رقم $id');
  }

  Future<void> _loadDocuments() async {
    final rows = await db.query('inventory_documents', where: 'inventory_type=?', whereArgs: [typeCode], orderBy: 'inventory_date DESC', limit: 300);
    if (mounted) setState(() => documents = rows);
  }

  Future<void> _openDocument(Map<String, Object?> doc) async {
    final id = (doc['id'] as num).toInt();
    final rows = await db.query('inventory_items', where: 'document_id=?', whereArgs: [id], orderBy: 'id');
    if (!mounted) return;
    setState(() {
      documentId = id; number.text = (doc['document_no'] ?? '').toString();
      status = (doc['status'] ?? 'مسودة').toString();
      notes.text = (doc['notes'] ?? '').toString();
      warehouseId = (doc['warehouse_id'] as num?)?.toInt();
      inventoryDate = DateTime.tryParse((doc['inventory_date'] ?? '').toString()) ?? DateTime.now();
      selectedMonth = inventoryDate.month; selectedYear = inventoryDate.year;
      items = rows.map((r) => Map<String, Object?>.from(r)).toList();
      selectedItemId = null;
    });
    msg('تم فتح مستند الجرد');
  }

  Future<void> _loadProducts() async {
    if (documentId == null) { msg('أنشئ مستندًا جديدًا أولًا'); return; }
    if (status != 'مسودة') { msg('لا يمكن تغيير أصناف مستند غير مسودة'); return; }
    if (warehouseId == null) { msg('حدد المخزن'); return; }
    final existing = items.map((r) => (r['product_id'] as num).toInt()).toSet();
    final stocks = await db.query('inventory', where: 'warehouse_id=?', whereArgs: [warehouseId]);
    final qtyByProduct = <int, double>{for (final r in stocks) (r['product_id'] as num).toInt(): n(r['qty'])};
    final maxRows = int.tryParse(limit.text) ?? 500;
    final filtered = products.where((p) {
      if (categoryId != null && (p['category_id'] as num?)?.toInt() != categoryId) return false;
      final q = search.text.trim().toLowerCase();
      final productId = (p['id'] as num).toInt();
      final barcodeMatch = barcodes.any((b) => (b['product_id'] as num?)?.toInt() == productId && (b['barcode'] ?? '').toString().toLowerCase().contains(q));
      final matches = q.isEmpty || (p['name'] ?? '').toString().toLowerCase().contains(q) || (p['code'] ?? '').toString().toLowerCase().contains(q) || barcodeMatch;
      return matches && (includeZero || (qtyByProduct[(p['id'] as num).toInt()] ?? 0) != 0);
    }).take(maxRows.clamp(1, 5000)).toList();
    var added = 0;
    for (final p in filtered) {
      final productId = (p['id'] as num).toInt();
      if (existing.contains(productId)) continue;
      final book = qtyByProduct[productId] ?? 0;
      await db.insert('inventory_items', {
        'document_id': documentId, 'product_id': productId,
        'book_qty': book, 'count_qty': book, 'count_qty2': book,
        'difference': 0, 'difference_cost': 0, 'counted': 0,
      });
      added++;
    }
    final rows = await db.query('inventory_items', where: 'document_id=?', whereArgs: [documentId], orderBy: 'id');
    if (mounted) setState(() => items = rows.map((r) => Map<String, Object?>.from(r)).toList());
    msg('تم تحميل $added صنفًا إلى مستند الجرد');
  }

  Future<bool> _save() async {
    if (documentId == null) { msg('أنشئ مستندًا أولًا'); return false; }
    if (status != 'مسودة') { msg('لا يمكن تعديل مستند إلا إذا كان مسودة'); return false; }
    setState(() => busy = true);
    try {
      await db.update('inventory_documents', {
        'document_no': number.text.trim().isEmpty ? 'CNT-$documentId' : number.text.trim(),
        'inventory_date': dateText(inventoryDate), 'warehouse_id': warehouseId,
        'notes': notes.text.trim(),
      }, where: 'id=?', whereArgs: [documentId]);
      for (final item in items) {
        final book = n(item['book_qty']), counted = n(item['count_qty']);
        final product = products.where((p) => (p['id'] as num).toInt() == (item['product_id'] as num).toInt()).firstOrNull;
        final cost = n(product?['cost_price']);
        await db.update('inventory_items', {
          'count_qty': counted, 'difference': counted - book, 'difference_cost': (counted - book) * cost, 'counted': (item['counted'] as num?)?.toInt() == 1 ? 1 : 0,
        }, where: 'id=?', whereArgs: [item['id']]);
      }
      await _loadDocuments();
      msg('تم حفظ مستند الجرد');
      return true;
    } catch (e) {
      msg('تعذر حفظ مستند الجرد: $e');
      return false;
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> _approve() async {
    if (documentId == null) { msg('حدد مستندًا'); return; }
    if (status != 'مسودة') { msg('يمكن اعتماد المسودة فقط'); return; }
    if (items.isEmpty) { msg('أضف أصناف الجرد أولًا'); return; }
    if (items.any((item) => (item['counted'] as num?)?.toInt() != 1)) {
      msg('أكمل العد الفعلي لكل الأصناف؛ إدخال الصفر يُحتسب عدًا صحيحًا');
      return;
    }
    if (!await _save()) return;
    final approverId = await _currentUserId();
    final changed = await db.update('inventory_documents', {'status': 'معتمد', 'approved_by': approverId}, where: 'id=? AND status=?', whereArgs: [documentId, 'مسودة']);
    if (changed != 1) { msg('لم يتم الاعتماد: تغيرت حالة المستند أو لم يعد مسودة'); await _loadDocuments(); return; }
    if (mounted) setState(() => status = 'معتمد');
    await _loadDocuments();
    msg('تم اعتماد مستند الجرد');
  }

  Future<void> _post() async {
    if (documentId == null) { msg('حدد مستندًا'); return; }
    if (status != 'معتمد') { msg('اعتمد المستند قبل ترحيله'); return; }
    setState(() => busy = true);
    try {
      final posterId = await _currentUserId();
      await db.postInventoryCount(documentId: documentId!, postedBy: posterId);
      if (mounted) setState(() => status = 'مرحل');
      await _loadDocuments();
      msg('تم ترحيل الجرد وتحديث أرصدة المخزون والقيود المحاسبية');
    } catch (e) { msg('تعذر ترحيل الجرد: $e'); }
    finally { if (mounted) setState(() => busy = false); }
  }

  void _recalculate() {
    setState(() {
      items = items.map((item) {
        final product = products.where((p) => (p['id'] as num?)?.toInt() == (item['product_id'] as num?)?.toInt()).firstOrNull;
        final difference = n(item['count_qty']) - n(item['book_qty']);
        return <String, Object?>{
          ...item,
          'difference': difference,
          'difference_cost': difference * n(product?['cost_price']),
        };
      }).toList();
    });
    msg('تمت إعادة حساب كميات الفروقات وقيمتها');
  }

  Future<void> _cancelDocument() async {
    if (documentId == null) { msg('حدد مستندًا أولًا'); return; }
    if (status == 'مرحل' || status == 'ملغي') { msg('لا يمكن إلغاء مستند مرحل أو ملغي'); return; }
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء مستند الجرد'),
        content: const Text('سيتم تغيير حالة المستند إلى ملغي ولن يمكن تعديله بعد ذلك.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('رجوع')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد الإلغاء')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final changed = await db.update('inventory_documents', {'status': 'ملغي'}, where: 'id=? AND status IN (?,?)', whereArgs: [documentId, 'مسودة', 'معتمد']);
    if (changed != 1) { msg('لم يتم الإلغاء؛ تحقق من حالة المستند'); await _loadDocuments(); return; }
    setState(() => status = 'ملغي');
    await _loadDocuments();
    msg('تم إلغاء مستند الجرد');
  }

  Future<void> _removeSelected() async {
    if (selectedItemId == null || status != 'مسودة') { msg('حدد سطرًا من مستند مسودة'); return; }
    await db.delete('inventory_items', where: 'id=? AND document_id=?', whereArgs: [selectedItemId, documentId]);
    if (mounted) setState(() { items.removeWhere((r) => r['id'] == selectedItemId); selectedItemId = null; });
  }

  Future<void> _pickDate() async {
    final value = await showDatePicker(context: context, initialDate: inventoryDate, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (value != null && mounted) setState(() { inventoryDate = value; selectedMonth = value.month; selectedYear = value.year; });
  }

  @override
  Future<void> _printPreview() async {
    final warehouse = warehouses.where((row) => (row['id'] as num?)?.toInt() == warehouseId).firstOrNull;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('معاينة طباعة $typeLabel'),
        content: SizedBox(
          width: 760,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('رقم المستند: ${number.text.trim().isEmpty ? '—' : number.text.trim()}'),
                Text('التاريخ: ${dateText(inventoryDate)}'),
                Text('المخزن: ${warehouse?['name'] ?? '—'}'),
                Text('الحالة: $status'),
                Text('عدد الأصناف: ${items.length}'),
                Text('الملاحظات: ${notes.text.trim().isEmpty ? '—' : notes.text.trim()}'),
                const Divider(height: 24),
                if (items.isEmpty)
                  const Text('لا توجد تفاصيل في المستند.')
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('الصنف')),
                        DataColumn(label: Text('الرصيد الدفتري')),
                        DataColumn(label: Text('المعدود')),
                        DataColumn(label: Text('الفرق')),
                        DataColumn(label: Text('قيمة الفرق')),
                      ],
                      rows: items.map((row) {
                        final product = products.where((p) => (p['id'] as num?)?.toInt() == (row['product_id'] as num?)?.toInt()).firstOrNull;
                        final difference = n(row['count_qty']) - n(row['book_qty']);
                        return DataRow(cells: [
                          DataCell(Text((product?['name'] ?? row['product_id'] ?? '—').toString())),
                          DataCell(Text(n(row['book_qty']).toStringAsFixed(2))),
                          DataCell(Text(n(row['count_qty']).toStringAsFixed(2))),
                          DataCell(Text(difference.toStringAsFixed(2))),
                          DataCell(Text(n(row['difference_cost']).toStringAsFixed(2))),
                        ]);
                      }).toList(),
                    ),
                  ),
                const SizedBox(height: 10),
                const Text('هذه معاينة للطباعة وليست إرسالًا مباشرًا إلى الطابعة.', style: TextStyle(color: Colors.blueGrey)),
              ],
            ),
          ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق'))],
      ),
    );
  }

  Widget build(BuildContext context) {
    final counted = items.where((r) => (r['counted'] as num?)?.toInt() == 1).length;
    final differences = items.where((r) => (n(r['count_qty']) - n(r['book_qty'])).abs() > 0.0001).toList();
    final increase = differences.fold<double>(0, (sum, r) => sum + (n(r['count_qty']) - n(r['book_qty']) > 0 ? n(r['count_qty']) - n(r['book_qty']) : 0));
    final decrease = differences.fold<double>(0, (sum, r) => sum + (n(r['count_qty']) - n(r['book_qty']) < 0 ? n(r['book_qty']) - n(r['count_qty']) : 0));
    final diffValue = differences.fold<double>(0, (sum, r) => sum + n(r['difference_cost']));
    final currentDocument = documents.where((d) => (d['id'] as num?)?.toInt() == documentId).firstOrNull;
    return ListView(padding: const EdgeInsets.all(18), children: [
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(typeLabel, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
          const Text('إدارة مستند الجرد ومقارنة الكمية الدفترية بالكمية الفعلية'),
        ])),
        Chip(label: Text(status), avatar: const Icon(Icons.fact_check_outlined, size: 18)),
      ]),
      if (currentDocument != null) Card(child: Padding(padding: const EdgeInsets.all(12), child: Wrap(spacing: 18, runSpacing: 8, children: [
        Text('المنشئ: ${_userName(currentDocument['created_by'])}'),
        Text('المعتمد: ${_userName(currentDocument['approved_by'])}'),
        Text('المرحل: ${_userName(currentDocument['posted_by'])}'),
      ]))),
      const SizedBox(height: 12),
      Card(child: Padding(padding: const EdgeInsets.all(14), child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(width: 220, child: DropdownButtonFormField<int>(
          value: warehouses.any((w) => (w['id'] as num).toInt() == warehouseId) ? warehouseId : null,
          decoration: const InputDecoration(labelText: 'المخزن', border: OutlineInputBorder()),
          items: warehouses.map((w) => DropdownMenuItem(value: (w['id'] as num).toInt(), child: Text((w['name'] ?? '').toString()))).toList(),
          onChanged: status == 'مسودة' ? (v) => setState(() => warehouseId = v) : null,
        )),
        SizedBox(width: 220, child: TextField(controller: number, enabled: status == 'مسودة', decoration: const InputDecoration(labelText: 'رقم المستند', border: OutlineInputBorder()))),
        OutlinedButton.icon(onPressed: status == 'مسودة' ? _pickDate : null, icon: const Icon(Icons.calendar_month), label: Text(dateText(inventoryDate))),
        if (widget.countType == 'monthlycount') SizedBox(width: 170, child: DropdownButtonFormField<int>(
          value: selectedMonth,
          decoration: const InputDecoration(labelText: 'الشهر', border: OutlineInputBorder()),
          items: List.generate(12, (i) => i + 1).map((m) => DropdownMenuItem(value: m, child: Text('الشهر ${m.toString().padLeft(2, '0')}'))).toList(),
          onChanged: status != 'مسودة' ? null : (m) { if (m != null) setState(() { selectedMonth = m; inventoryDate = DateTime(selectedYear, selectedMonth, 1); }); },
        )),
        if (widget.countType == 'monthlycount' || widget.countType == 'yearlycount') SizedBox(width: 150, child: DropdownButtonFormField<int>(
          value: selectedYear,
          decoration: const InputDecoration(labelText: 'السنة', border: OutlineInputBorder()),
          items: List.generate(21, (i) => DateTime.now().year - 10 + i).map((y) => DropdownMenuItem(value: y, child: Text(y.toString()))).toList(),
          onChanged: status != 'مسودة' ? null : (y) { if (y != null) setState(() { selectedYear = y; inventoryDate = widget.countType == 'monthlycount' ? DateTime(selectedYear, selectedMonth, 1) : DateTime(selectedYear, 1, 1); }); },
        )),
        SizedBox(width: 120, child: TextField(controller: limit, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'حد التحميل', border: OutlineInputBorder()))),
        OutlinedButton.icon(onPressed: busy ? null : _newDocument, icon: const Icon(Icons.add), label: const Text('مستند جديد')),
        OutlinedButton.icon(onPressed: busy ? null : () async {
          final picked = await showDialog<Map<String, Object?>>(context: context, builder: (ctx) => SimpleDialog(
            title: const Text('فتح مستند جرد'), children: documents.map((d) => SimpleDialogOption(onPressed: () => Navigator.pop(ctx, d), child: Text('${d['document_no']} • ${d['inventory_date']} • ${d['status']}'))).toList(),
          ));
          if (picked != null) await _openDocument(picked);
        }, icon: const Icon(Icons.folder_open), label: const Text('فتح مستند')),
        OutlinedButton.icon(onPressed: busy ? null : _load, icon: const Icon(Icons.refresh), label: const Text('تحديث')),
      ]))),
      Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('معايير تحميل الأصناف', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(width: 280, child: TextField(controller: search, decoration: const InputDecoration(labelText: 'بحث بالاسم أو الكود أو الباركود', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()))),
          SizedBox(width: 220, child: DropdownButtonFormField<int?>(
            value: categoryId, decoration: const InputDecoration(labelText: 'القسم', border: OutlineInputBorder()),
            items: [const DropdownMenuItem<int?>(value: null, child: Text('كل الأقسام')), ...categories.map((c) => DropdownMenuItem<int?>(value: (c['id'] as num).toInt(), child: Text((c['name'] ?? '').toString())))],
            onChanged: (v) => setState(() => categoryId = v),
          )),
          FilterChip(label: const Text('تضمين الأرصدة الصفرية'), selected: includeZero, onSelected: (v) => setState(() => includeZero = v)),
          FilledButton.icon(onPressed: busy ? null : _loadProducts, icon: const Icon(Icons.download), label: const Text('تحميل الأصناف')),
          OutlinedButton.icon(onPressed: busy ? null : _removeSelected, icon: const Icon(Icons.remove_circle_outline), label: const Text('إزالة المحدد')),
        ]),
      ]))),
      GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: MediaQuery.sizeOf(context).width > 1200 ? 4 : 2, childAspectRatio: 2.5, crossAxisSpacing: 10, mainAxisSpacing: 10, children: [
        _stat('عدد الأصناف', '${items.length}', Icons.inventory_2),
        _stat('الأصناف المعدودة', '$counted', Icons.check_circle_outline),
        _stat('سطور الفروقات', '${differences.length}', Icons.compare_arrows),
        _stat('قيمة الفروقات', diffValue.toStringAsFixed(2), Icons.calculate),
      ]),
      Card(child: Padding(padding: const EdgeInsets.all(10), child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(columns: const [
        DataColumn(label: Text('تحديد')), DataColumn(label: Text('الصنف')), DataColumn(label: Text('الرصيد الدفتري')), DataColumn(label: Text('الكمية المعدودة')), DataColumn(label: Text('الفرق')), DataColumn(label: Text('قيمة الفرق')),
      ], rows: items.map((r) {
        final product = products.where((p) => (p['id'] as num).toInt() == (r['product_id'] as num).toInt()).firstOrNull;
        final difference = n(r['count_qty']) - n(r['book_qty']);
        final selected = selectedItemId == (r['id'] as num).toInt();
        return DataRow(selected: selected, onSelectChanged: (_) => setState(() => selectedItemId = (r['id'] as num).toInt()), cells: [
          DataCell(Checkbox(value: selected, onChanged: (_) => setState(() => selectedItemId = (r['id'] as num).toInt()))),
          DataCell(Text('${product?['name'] ?? r['product_id']}')),
          DataCell(Text(n(r['book_qty']).toStringAsFixed(2))),
          DataCell(SizedBox(width: 120, child: TextFormField(
            key: ValueKey('count-${r['id']}'),
            initialValue: n(r['count_qty']).toStringAsFixed(2),
            enabled: status == 'مسودة',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
            onChanged: (v) { final idx = items.indexWhere((x) => x['id'] == r['id']); if (idx >= 0) { final countedValue = double.tryParse(v) ?? 0; final differenceValue = countedValue - n(r['book_qty']); setState(() { items[idx]['count_qty'] = countedValue; items[idx]['counted'] = 1; items[idx]['difference'] = differenceValue; items[idx]['difference_cost'] = differenceValue * n(product?['cost_price']); }); } },
          ))),
          DataCell(Text(difference.toStringAsFixed(2))),
          DataCell(Text((difference * n(product?['cost_price'])).toStringAsFixed(2))),
        ]);
      }).toList())))),
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Wrap(spacing: 10, runSpacing: 8, children: [
        OutlinedButton.icon(onPressed: busy || status != 'مسودة' ? null : _save, icon: const Icon(Icons.save_outlined), label: const Text('حفظ')),
        OutlinedButton.icon(onPressed: busy || status == 'ملغي' || status == 'مرحل' ? null : _cancelDocument, icon: const Icon(Icons.cancel_outlined), label: const Text('إلغاء')),
        OutlinedButton.icon(onPressed: busy || status != 'مسودة' ? null : _approve, icon: const Icon(Icons.verified_outlined), label: const Text('اعتماد')),
        FilledButton.icon(onPressed: busy || status != 'معتمد' ? null : _post, icon: const Icon(Icons.publish), label: const Text('ترحيل')),
        OutlinedButton.icon(onPressed: busy ? null : _recalculate, icon: const Icon(Icons.calculate_outlined), label: const Text('إعادة الحساب')),
        OutlinedButton.icon(onPressed: busy ? null : _printPreview, icon: const Icon(Icons.print_outlined), label: const Text('معاينة الطباعة')),
        OutlinedButton.icon(onPressed: busy ? null : _loadDocuments, icon: const Icon(Icons.list_alt), label: const Text('مستندات الجرد')),
        OutlinedButton.icon(onPressed: () => closeModule(context), icon: const Icon(Icons.close), label: const Text('إغلاق')),
      ]))),
      if (busy) const LinearProgressIndicator(),
      Text('ملخص الفرق: زيادة $increase • عجز $decrease • صافي قيمة الفرق ${diffValue.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600)),
      if (widget.countType == 'yearlycount') Text('نسبة الإنجاز: ${items.isEmpty ? 0 : (counted * 100 / items.length).round()}%'),
      if (widget.countType == 'monthlycount') Text('فترة الجرد: ${selectedYear}-${selectedMonth.toString().padLeft(2, '0')}'),
      TextField(controller: notes, enabled: status == 'مسودة', decoration: const InputDecoration(labelText: 'ملاحظات المستند', border: OutlineInputBorder())),
    ]);
  }

  Widget _stat(String title, String value, IconData icon) => Card(child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
    Icon(icon, size: 26), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(title, style: const TextStyle(color: Colors.blueGrey)), Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
    ])),
  ])));
}
