import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import '../../widgets/common_widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../data/database_helper.dart';

/// Report for existing inventory count documents and lines.
class CountReportsScreen extends StatefulWidget {
  const CountReportsScreen({super.key});
  @override
  State<CountReportsScreen> createState() => _CountReportsScreenState();
}

class _CountReportsScreenState extends State<CountReportsScreen> {
  final _db = DatabaseHelper.instance;
  final _search = TextEditingController();
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  String _type = 'الكل', _status = 'الكل';
  int? _warehouseId;
  bool _busy = false;
  List<Map<String, Object?>> _rows = [], _warehouses = [];

  int _id(Object? v) => (v as num?)?.toInt() ?? 0;
  double _n(Object? v) => (v as num?)?.toDouble() ?? 0;
  String _date(DateTime v) => v.toIso8601String().substring(0, 10);
  String _money(Object? v) => _n(v).toStringAsFixed(2);
  void _message(String s) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s))); }

  @override
  void initState() { super.initState(); _reload(); }
  @override
  void dispose() { _search.dispose(); super.dispose(); }

  Future<void> _reload() async {
    setState(() => _busy = true);
    try {
      final result = await Future.wait([
        _db.query('inventory_documents', orderBy: 'inventory_date DESC, id DESC'),
        _db.query('inventory_items', orderBy: 'id'),
        _db.query('products', orderBy: 'name'),
        _db.query('warehouses', orderBy: 'name'),
      ]);
      final docs = {for (final r in result[0]) _id(r['id']): r};
      final products = {for (final r in result[2]) _id(r['id']): r};
      final warehouses = result[3];
      final warehouseMap = {for (final r in warehouses) _id(r['id']): r};
      final rows = <Map<String, Object?>>[];
      for (final item in result[1]) {
        final doc = docs[_id(item['document_id'])];
        if (doc == null) continue;
        final rawDate = (doc['inventory_date'] ?? '').toString();
        if (rawDate.length < 10) continue;
        final date = rawDate.substring(0, 10);
        final type = (doc['inventory_type'] ?? '').toString();
        final status = (doc['status'] ?? 'مسودة').toString();
        final warehouseId = _id(doc['warehouse_id']);
        if (date.compareTo(_date(_from)) < 0 || date.compareTo(_date(_to)) > 0) continue;
        if (_type != 'الكل' && type != _type) continue;
        if (_status != 'الكل' && status != _status) continue;
        if (_warehouseId != null && warehouseId != _warehouseId) continue;
        final product = products[_id(item['product_id'])];
        final warehouse = warehouseMap[warehouseId];
        final name = (product?['name'] ?? '—').toString();
        final code = (product?['code'] ?? '—').toString();
        final docNo = (doc['document_no'] ?? '—').toString();
        final q = _search.text.trim().toLowerCase();
        if (q.isNotEmpty && !('$name $code $docNo $type $status ' + (warehouse?['name'] ?? '').toString()).toLowerCase().contains(q)) continue;
        rows.add({
          'document_no': docNo, 'inventory_date': date, 'inventory_type': type, 'status': status,
          'warehouse': warehouse?['name'] ?? '—', 'product_name': name, 'product_code': code,
          'book_qty': item['book_qty'] ?? 0, 'count_qty': item['count_qty'] ?? 0,
          'difference': item['difference'] ?? 0, 'difference_cost': item['difference_cost'] ?? 0,
        });
      }
      if (mounted) setState(() { _rows = rows; _warehouses = warehouses; });
    } catch (e) {
      _message('تعذر تحميل تقارير الجرد: ' + e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDate(bool from) async {
    final picked = await showDatePicker(context: context, initialDate: from ? _from : _to, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (picked == null || !mounted) return;
    setState(() {
      if (from) { _from = picked; if (_from.isAfter(_to)) _to = _from; }
      else { _to = picked; if (_to.isBefore(_from)) _from = _to; }
    });
    await _reload();
  }

  CellValue _excelCell(Object? value) {
    if (value == null) return TextCellValue('');
    if (value is bool) return BoolCellValue(value);
    if (value is int) return IntCellValue(value);
    if (value is num) return DoubleCellValue(value.toDouble());
    return TextCellValue(value.toString());
  }

  Future<void> _export() async {
    if (_rows.isEmpty) { _message('لا توجد بيانات لتصديرها'); return; }
    try {
      final docs = await getApplicationDocumentsDirectory();
      final folder = Directory(p.join(docs.path, 'StoreERP', 'exports'));
      await folder.create(recursive: true);
      final file = File(p.join(folder.path, 'inventory_count_report_' + DateTime.now().millisecondsSinceEpoch.toString() + '.xlsx'));
      final header = ['رقم المستند', 'التاريخ', 'نوع الجرد', 'الحالة', 'المخزن', 'الصنف', 'الكود', 'الرصيد الدفتري', 'الكمية المعدودة', 'الفرق', 'قيمة الفرق'];
      final data = _rows.map((r) => [r['document_no'], r['inventory_date'], r['inventory_type'], r['status'], r['warehouse'], r['product_name'], r['product_code'], r['book_qty'], r['count_qty'], r['difference'], r['difference_cost']]).toList();
      final workbook = Excel.createExcel();
      final sheet = workbook['تقرير الجرد'];
      sheet.appendRow(header.map(_excelCell).toList());
      for (final row in data) {
        sheet.appendRow(row.map(_excelCell).toList());
      }
      final bytes = workbook.encode();
      if (bytes == null) throw StateError('تعذر إنشاء ملف Excel');
      await file.writeAsBytes(bytes, flush: true);
      _message('تم تصدير ملف Excel: ' + file.path);
    } catch (e) {
      _message('تعذر تصدير تقرير الجرد: ' + e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final increase = _rows.where((r) => _n(r['difference']) > 0).fold<double>(0, (s, r) => s + _n(r['difference']));
    final decrease = _rows.where((r) => _n(r['difference']) < 0).fold<double>(0, (s, r) => s + _n(r['difference']).abs());
    final value = _rows.fold<double>(0, (s, r) => s + _n(r['difference_cost']));
    return ListView(padding: const EdgeInsets.all(18), children: [
      Row(children: [
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('تقارير الجرد', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
          SizedBox(height: 4), Text('تحليل فروق الجرد حسب الفترة والنوع والمخزن وحالة المستند'),
        ])),
        OutlinedButton.icon(onPressed: _busy ? null : _reload, icon: const Icon(Icons.refresh), label: const Text('تحديث')),
        const SizedBox(width: 8),
        FilledButton.icon(onPressed: _busy ? null : _export, icon: const Icon(Icons.file_download_outlined), label: const Text('تصدير Excel (.xlsx)')),
        const SizedBox(width: 8),
        OutlinedButton.icon(onPressed: () => closeModule(context), icon: const Icon(Icons.close), label: const Text('إغلاق')),
      ]),
      const SizedBox(height: 12),
      Card(child: Padding(padding: const EdgeInsets.all(14), child: Wrap(spacing: 12, runSpacing: 12, children: [
        OutlinedButton.icon(onPressed: _busy ? null : () => _pickDate(true), icon: const Icon(Icons.calendar_month), label: Text('من: ' + _date(_from))),
        OutlinedButton.icon(onPressed: _busy ? null : () => _pickDate(false), icon: const Icon(Icons.calendar_month), label: Text('إلى: ' + _date(_to))),
        SizedBox(width: 170, child: DropdownButtonFormField<String>(value: _type, decoration: const InputDecoration(labelText: 'نوع الجرد', border: OutlineInputBorder()), items: const ['الكل', 'فعلي', 'يومي', 'شهري', 'سنوي'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: _busy ? null : (v) { setState(() => _type = v ?? 'الكل'); _reload(); })),
        SizedBox(width: 170, child: DropdownButtonFormField<String>(value: _status, decoration: const InputDecoration(labelText: 'حالة المستند', border: OutlineInputBorder()), items: const ['الكل', 'مسودة', 'معتمد', 'مرحل', 'ملغي'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: _busy ? null : (v) { setState(() => _status = v ?? 'الكل'); _reload(); })),
        SizedBox(width: 210, child: DropdownButtonFormField<int?>(value: _warehouseId, decoration: const InputDecoration(labelText: 'المخزن', border: OutlineInputBorder()), items: [const DropdownMenuItem<int?>(value: null, child: Text('كل المخازن')), ..._warehouses.map((w) => DropdownMenuItem<int?>(value: _id(w['id']), child: Text((w['name'] ?? '').toString())))], onChanged: _busy ? null : (v) { setState(() => _warehouseId = v); _reload(); })),
        SizedBox(width: 250, child: TextField(controller: _search, decoration: const InputDecoration(labelText: 'بحث بالصنف أو المستند أو الكود', border: OutlineInputBorder(), prefixIcon: Icon(Icons.search)), onSubmitted: (_) => _reload())),
        OutlinedButton.icon(onPressed: _busy ? null : () { setState(() { _from = DateTime(DateTime.now().year, DateTime.now().month, 1); _to = DateTime.now(); _type = 'الكل'; _status = 'الكل'; _warehouseId = null; _search.clear(); }); _reload(); }, icon: const Icon(Icons.filter_alt_off), label: const Text('مسح الفلاتر')),
      ]))),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _metric('عدد سطور الجرد', _rows.length.toString(), Icons.table_rows_outlined),
        _metric('إجمالي الزيادة', _money(increase), Icons.trending_up),
        _metric('إجمالي العجز', _money(decrease), Icons.trending_down),
        _metric('صافي قيمة الفروق', _money(value), Icons.account_balance_wallet_outlined),
      ]),
      if (_busy) const LinearProgressIndicator(),
      const SizedBox(height: 8),
      Card(child: Padding(padding: const EdgeInsets.all(12), child: _rows.isEmpty
        ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('لا توجد نتائج مطابقة للفلاتر')))
        : SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(
            columns: const [
              DataColumn(label: Text('المستند')), DataColumn(label: Text('التاريخ')), DataColumn(label: Text('النوع')),
              DataColumn(label: Text('الحالة')), DataColumn(label: Text('المخزن')), DataColumn(label: Text('الصنف')),
              DataColumn(label: Text('الكود')), DataColumn(label: Text('الدفتري')), DataColumn(label: Text('المعدود')),
              DataColumn(label: Text('الفرق')), DataColumn(label: Text('قيمة الفرق')),
            ],
            rows: _rows.map((r) => DataRow(cells: [
              DataCell(Text((r['document_no'] ?? '—').toString())),
              DataCell(Text((r['inventory_date'] ?? '—').toString())),
              DataCell(Text((r['inventory_type'] ?? '—').toString())),
              DataCell(Text((r['status'] ?? '—').toString())),
              DataCell(Text((r['warehouse'] ?? '—').toString())),
              DataCell(Text((r['product_name'] ?? '—').toString())),
              DataCell(Text((r['product_code'] ?? '—').toString())),
              DataCell(Text(_money(r['book_qty']))), DataCell(Text(_money(r['count_qty']))),
              DataCell(Text(_money(r['difference']))), DataCell(Text(_money(r['difference_cost']))),
            ])).toList(),
          )))),
    ]);
  }

  Widget _metric(String title, String value, IconData icon) => SizedBox(width: 220, child: Card(child: ListTile(
    leading: Icon(icon), title: Text(title), subtitle: Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
  )));
}
