import 'package:flutter/material.dart';
import '../../widgets/common_widgets.dart';
import '../../data/database_helper.dart';
import 'inventory_count_screen.dart';

class InventoryDocumentsScreen extends StatefulWidget {
  const InventoryDocumentsScreen({super.key});
  @override
  State<InventoryDocumentsScreen> createState() => _InventoryDocumentsScreenState();
}

class _InventoryDocumentsScreenState extends State<InventoryDocumentsScreen> {
  final db = DatabaseHelper.instance;
  List<Map<String, Object?>> docs = [], warehouses = [];
  int? warehouseId, selectedId;
  String typeFilter = 'الكل', statusFilter = 'الكل';
  DateTime? fromDate, toDate;
  bool useDate = false, busy = false;
  final limit = TextEditingController(text: '300');
  String dateText(DateTime d) => d.toIso8601String().substring(0, 10);
  void msg(String s) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s))); }

  @override
  void initState() { super.initState(); _reload(); }
  @override
  void dispose() { limit.dispose(); super.dispose(); }

  Future<void> _reload() async {
    setState(() => busy = true);
    try {
      final w = await db.query('warehouses', where: 'is_active=1', orderBy: 'name');
      final rows = await db.query('inventory_documents', orderBy: 'inventory_date DESC', limit: (int.tryParse(limit.text) ?? 300).clamp(1, 5000));
      if (mounted) setState(() { warehouses = w; docs = rows; });
    } catch (e) { msg('تعذر تحديث قائمة مستندات الجرد: $e'); }
    finally { if (mounted) setState(() => busy = false); }
  }

  List<Map<String, Object?>> get visible => docs.where((d) {
    final warehouse = (d['warehouse_id'] as num?)?.toInt();
    final type = (d['inventory_type'] ?? '').toString();
    final status = (d['status'] ?? '').toString();
    final date = (d['inventory_date'] ?? '').toString();
    final typeOk = typeFilter == 'الكل' || type == typeFilter;
    final statusOk = statusFilter == 'الكل' || status == statusFilter;
    final warehouseOk = warehouseId == null || warehouse == warehouseId;
    final fromOk = !useDate || fromDate == null || date.compareTo(dateText(fromDate!)) >= 0;
    final toOk = !useDate || toDate == null || date.compareTo(dateText(toDate!)) <= 0;
    return typeOk && statusOk && warehouseOk && fromOk && toOk;
  }).toList();

  int countStatus(String status) => visible.where((d) => d['status'] == status).length;

  Future<void> _chooseDate(bool from) async {
    final current = from ? fromDate : toDate;
    final picked = await showDatePicker(context: context, initialDate: current ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (picked != null && mounted) setState(() { if (from) fromDate = picked; else toDate = picked; });
  }

  Future<void> _open(Map<String, Object?> doc) async {
    final id = (doc['id'] as num).toInt();
    final type = switch ((doc['inventory_type'] ?? '').toString()) {
      'يومي' => 'dailycount', 'شهري' => 'monthlycount', 'سنوي' => 'yearlycount', _ => 'counts',
    };
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InventoryCountScreen(countType: type, initialDocumentId: id)));
    await _reload();
  }

  Future<void> _new(String type) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InventoryCountScreen(countType: type)));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final rows = visible;
    return ListView(padding: const EdgeInsets.all(18), children: [
      Row(children: [
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('متابعة مستندات الجرد', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
          SizedBox(height: 4), Text('بحث ومتابعة المسودات والمستندات المعتمدة والمرحلة'),
        ])),
        OutlinedButton.icon(onPressed: busy ? null : _reload, icon: const Icon(Icons.refresh), label: const Text('تحديث')),
      ]),
      const SizedBox(height: 12),
      Card(child: Padding(padding: const EdgeInsets.all(14), child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(width: 210, child: DropdownButtonFormField<int?>(value: warehouseId, decoration: const InputDecoration(labelText: 'المخزن', border: OutlineInputBorder()), items: [const DropdownMenuItem<int?>(value: null, child: Text('كل المخازن')), ...warehouses.map((w) => DropdownMenuItem<int?>(value: (w['id'] as num).toInt(), child: Text((w['name'] ?? '').toString())))], onChanged: (v) => setState(() => warehouseId = v))),
        SizedBox(width: 190, child: DropdownButtonFormField<String>(value: typeFilter, decoration: const InputDecoration(labelText: 'نوع الجرد', border: OutlineInputBorder()), items: const ['الكل','فعلي','يومي','شهري','سنوي'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => setState(() => typeFilter = v ?? 'الكل'))),
        SizedBox(width: 190, child: DropdownButtonFormField<String>(value: statusFilter, decoration: const InputDecoration(labelText: 'الحالة', border: OutlineInputBorder()), items: const ['الكل','مسودة','معتمد','مرحل','ملغي'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => setState(() => statusFilter = v ?? 'الكل'))),
        FilterChip(label: const Text('تفعيل فلتر التاريخ'), selected: useDate, onSelected: (v) => setState(() => useDate = v)),
        OutlinedButton.icon(onPressed: () => _chooseDate(true), icon: const Icon(Icons.calendar_today), label: Text(fromDate == null ? 'من تاريخ' : dateText(fromDate!))),
        OutlinedButton.icon(onPressed: () => _chooseDate(false), icon: const Icon(Icons.event), label: Text(toDate == null ? 'إلى تاريخ' : dateText(toDate!))),
        SizedBox(width: 110, child: TextField(controller: limit, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'حد النتائج', border: OutlineInputBorder()))),
        FilledButton.icon(onPressed: busy ? null : _reload, icon: const Icon(Icons.search), label: const Text('عرض')),
      ]))),
      GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: MediaQuery.sizeOf(context).width > 1100 ? 4 : 2, childAspectRatio: 2.7, crossAxisSpacing: 10, mainAxisSpacing: 10, children: [
        _stat('عدد النتائج', '${rows.length}', Icons.list_alt),
        _stat('مسودات', '${countStatus('مسودة')}', Icons.edit_note),
        _stat('معتمد', '${countStatus('معتمد')}', Icons.verified_outlined),
        _stat('مرحل', '${countStatus('مرحل')}', Icons.check_circle_outline),
      ]),
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(onPressed: selectedId == null ? null : () { final doc = rows.where((r) => (r['id'] as num).toInt() == selectedId).firstOrNull; if (doc != null) _open(doc); }, icon: const Icon(Icons.open_in_new), label: const Text('فتح المحدد')),
        OutlinedButton.icon(onPressed: () => _new('dailycount'), icon: const Icon(Icons.today), label: const Text('جرد يومي جديد')),
        OutlinedButton.icon(onPressed: () => _new('monthlycount'), icon: const Icon(Icons.calendar_month), label: const Text('جرد شهري جديد')),
        OutlinedButton.icon(onPressed: () => _new('yearlycount'), icon: const Icon(Icons.event), label: const Text('جرد سنوي جديد')),
      ]))),
      Card(child: Padding(padding: const EdgeInsets.all(10), child: rows.isEmpty ? const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('لا توجد مستندات مطابقة للفلاتر'))) : SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(columns: const [
        DataColumn(label: Text('تحديد')), DataColumn(label: Text('رقم المستند')), DataColumn(label: Text('التاريخ')), DataColumn(label: Text('المخزن')), DataColumn(label: Text('النوع')), DataColumn(label: Text('الحالة')), DataColumn(label: Text('فتح')),
      ], rows: rows.map((d) {
        final id = (d['id'] as num).toInt();
        final warehouse = warehouses.where((w) => (w['id'] as num).toInt() == (d['warehouse_id'] as num?)?.toInt()).map((w) => (w['name'] ?? '').toString()).firstOrNull ?? '—';
        return DataRow(selected: id == selectedId, onSelectChanged: (_) => setState(() => selectedId = id), cells: [
          DataCell(Checkbox(value: selectedId == id, onChanged: (_) => setState(() => selectedId = id))),
          DataCell(Text((d['document_no'] ?? '—').toString())),
          DataCell(Text((d['inventory_date'] ?? '—').toString())),
          DataCell(Text(warehouse)),
          DataCell(Text((d['inventory_type'] ?? '—').toString())),
          DataCell(Text((d['status'] ?? '—').toString())),
          DataCell(IconButton(tooltip: 'فتح المحدد', onPressed: () => _open(d), icon: const Icon(Icons.open_in_new))),
        ]);
      }).toList())))),
      if (busy) const LinearProgressIndicator(),
      Align(alignment: AlignmentDirectional.centerEnd, child: TextButton.icon(onPressed: () => closeModule(context), icon: const Icon(Icons.close), label: const Text('إغلاق'))),
    ]);
  }

  Widget _stat(String title, String value, IconData icon) => Card(child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
    Icon(icon), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text(title, style: const TextStyle(color: Colors.blueGrey)), Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))])),
  ])));
}
