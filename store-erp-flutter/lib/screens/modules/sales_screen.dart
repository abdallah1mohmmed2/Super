import 'package:flutter/material.dart';
import '../../data/database_helper.dart';

/// Full sales invoice workflow backed by sales_header, sales_lines,
/// document_payments, inventory, cash_boxes and customers.
class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});
  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  final _invoiceNo = TextEditingController();
  final _notes = TextEditingController();
  final _search = TextEditingController();
  final _qty = TextEditingController(text: '1');
  final _price = TextEditingController();
  final _lineDiscount = TextEditingController(text: '0');
  final _lineTax = TextEditingController(text: '0');
  final _paymentAmount = TextEditingController();
  final _paymentReference = TextEditingController();
  DateTime _date = DateTime.now();
  List<Map<String, Object?>> _warehouses = [];
  List<Map<String, Object?>> _customers = [];
  List<Map<String, Object?>> _cashBoxes = [];
  List<Map<String, Object?>> _products = [];
  List<Map<String, Object?>> _invoices = [];
  final List<Map<String, Object?>> _lines = [];
  final List<Map<String, Object?>> _payments = [];
  int? _warehouseId, _customerId, _cashBoxId, _editingLine;
  int? _saleId;
  String _paymentMethod = 'نقدي';
  String _status = 'مسودة';
  bool _busy = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _invoiceNo.text = _newInvoiceNo();
    _loadReferences();
  }

  String _newInvoiceNo() => 'S-${DateTime.now().millisecondsSinceEpoch}';
  double _num(String? s) => double.tryParse((s ?? '').trim()) ?? 0;
  double _v(Object? value) => value is num ? value.toDouble() : 0;
  String _money(double value) => value.toStringAsFixed(2);
  String _dateString(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  double get _subtotal => _lines.fold(0, (sum, line) => sum + _v(line['gross']));
  double get _discount => _lines.fold(0, (sum, line) => sum + _v(line['discount']));
  double get _tax => _lines.fold(0, (sum, line) => sum + _v(line['tax']));
  double get _net => (_subtotal - _discount + _tax).clamp(0, double.infinity).toDouble();
  double get _paid => _payments.fold(0, (sum, p) => sum + _v(p['amount']));
  double get _remaining => _net - _paid;

  Future<void> _loadReferences() async {
    setState(() => _loading = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final wh = await db.query('warehouses', where: 'is_active=1', orderBy: 'name');
      final cu = await db.query('customers', where: 'is_active=1 AND is_suspended=0', orderBy: 'name');
      final cb = await db.query('cash_boxes', where: 'is_active=1', orderBy: 'name');
      if (!mounted) return;
      setState(() {
        _warehouses = wh; _customers = cu; _cashBoxes = cb;
        _warehouseId ??= wh.isEmpty ? null : (wh.first['id'] as num).toInt();
        _cashBoxId ??= cb.isEmpty ? null : (cb.first['id'] as num).toInt();
        _loading = false;
      });
    } catch (e) {
      if (mounted) { setState(() => _loading = false); _message('تعذر تحميل القوائم: $e'); }
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _searchProducts() async {
    final term = _search.text.trim();
    if (term.isEmpty) { _message('اكتب اسم الصنف أو الكود أو الباركود'); return; }
    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.rawQuery('''
        SELECT DISTINCT p.id, p.code, p.name, p.unit, p.sale_price, p.cost_price,
          COALESCE(i.qty,0) AS stock
        FROM products p
        LEFT JOIN barcodes b ON b.product_id=p.id
        LEFT JOIN inventory i ON i.product_id=p.id AND i.warehouse_id=?
        WHERE p.is_active=1 AND (p.name LIKE ? OR p.code LIKE ? OR b.barcode LIKE ?)
        ORDER BY p.name LIMIT 50
      ''', [_warehouseId, '%$term%', '%$term%', '%$term%']);
      if (!mounted) return;
      setState(() => _products = rows);
      if (rows.isEmpty) _message('لا توجد أصناف مطابقة');
    } catch (e) { _message('تعذر البحث عن الأصناف: $e'); }
  }

  void _chooseProduct(Map<String, Object?> product) {
    setState(() {
      _search.text = (product['name'] ?? '').toString();
      _price.text = _money(_v(product['sale_price']));
      _qty.text = '1'; _lineDiscount.text = '0'; _lineTax.text = '0';
      _editingLine = null;
    });
  }

  void _addOrUpdateLine() {
    final selected = _products.where((p) => p['name'] == _search.text.trim() ||
      (p['code'] ?? '').toString() == _search.text.trim()).toList();
    if (selected.isEmpty) { _message('ابحث عن الصنف ثم اختره من نتائج البحث'); return; }
    final product = selected.first;
    final qty = _num(_qty.text), price = _num(_price.text);
    final discount = _num(_lineDiscount.text), tax = _num(_lineTax.text);
    if (qty <= 0 || price < 0 || discount < 0 || tax < 0) {
      _message('تحقق من الكمية والسعر والخصم والضريبة'); return;
    }
    final gross = qty * price;
    if (discount > gross) { _message('خصم السطر لا يمكن أن يتجاوز إجماليه'); return; }
    final line = <String, Object?>{
      'product_id': (product['id'] as num).toInt(),
      'code': product['code'] ?? '',
      'name': product['name'] ?? '',
      'unit': product['unit'] ?? 'قطعة',
      'qty': qty, 'factor': 1.0, 'price': price,
      'discount': discount, 'tax': tax, 'gross': gross,
      'line_total': gross - discount + tax,
      'stock': _v(product['stock']),
    };
    setState(() {
      if (_editingLine != null && _editingLine! < _lines.length) {
        _lines[_editingLine!] = line;
      } else {
        _lines.add(line);
      }
      _editingLine = null;
      _search.clear(); _qty.text = '1'; _price.clear();
      _lineDiscount.text = '0'; _lineTax.text = '0'; _products = [];
    });
  }

  void _editLine(int index) {
    final line = _lines[index];
    setState(() {
      _editingLine = index;
      _search.text = (line['name'] ?? '').toString();
      _qty.text = _money(_v(line['qty']));
      _price.text = _money(_v(line['price']));
      _lineDiscount.text = _money(_v(line['discount']));
      _lineTax.text = _money(_v(line['tax']));
      _products = [Map<String, Object?>.from(line)];
    });
  }

  void _removeLine(int index) => setState(() {
    _lines.removeAt(index);
    _editingLine = null;
  });

  Future<void> _addPayment() async {
    final amount = _num(_paymentAmount.text);
    if (amount <= 0) { _message('أدخل مبلغ دفعة أكبر من صفر'); return; }
    if (_paid + amount > _net + 0.005) { _message('مجموع الدفعات لا يمكن أن يتجاوز صافي الفاتورة'); return; }
    setState(() {
      _payments.add({'method': _paymentMethod, 'amount': amount,
        'reference': _paymentReference.text.trim()});
      _paymentAmount.clear(); _paymentReference.clear();
    });
  }

  Future<void> _save({required bool post}) async {
    if (_busy) return;
    if (_invoiceNo.text.trim().isEmpty || _warehouseId == null || _cashBoxId == null) {
      _message('رقم الفاتورة والمخزن والصندوق مطلوبة'); return;
    }
    if (_lines.isEmpty) { _message('أضف صنفًا واحدًا على الأقل'); return; }
    if (_paid > _net + 0.005) { _message('المدفوع أكبر من صافي الفاتورة'); return; }
    if (post && _payments.isEmpty && _paid == 0) {
      final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('ترحيل دون دفعة؟'),
        content: const Text('لم تسجل دفعة. ستُسجل الفاتورة كذمم على العميل إن كان محددًا. هل تريد المتابعة؟'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('رجوع')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('متابعة'))],
      ));
      if (confirm != true) return;
    }
    setState(() => _busy = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final date = _dateString(_date);
      await db.transaction((txn) async {
        final header = <String, Object?>{
          'invoice_no': _invoiceNo.text.trim(), 'invoice_date': date,
          'customer_id': _customerId, 'warehouse_id': _warehouseId,
          'cash_box_id': _cashBoxId, 'payment_method': _paymentMethod,
          'subtotal': _subtotal, 'discount': _discount, 'tax': _tax,
          'net': _net, 'paid': _paid, 'status': 'مسودة',
          'notes': _notes.text.trim(),
        };
        if (_saleId == null) {
          _saleId = await txn.insert('sales_header', header);
        } else {
          final existing = await txn.query('sales_header', where: 'id=?', whereArgs: [_saleId], limit: 1);
          if (existing.isEmpty) throw StateError('الفاتورة غير موجودة');
          if (existing.first['status'] == 'مرحل') throw StateError('لا يمكن تعديل فاتورة مرحلة');
          await txn.update('sales_header', header, where: 'id=?', whereArgs: [_saleId]);
          await txn.delete('sales_lines', where: 'sales_id=?', whereArgs: [_saleId]);
          await txn.delete('document_payments', where: 'document_type=? AND document_id=?', whereArgs: ['sales', _saleId]);
        }
        for (final line in _lines) {
          await txn.insert('sales_lines', {
            'sales_id': _saleId, 'product_id': line['product_id'],
            'unit': line['unit'], 'factor': line['factor'], 'qty': line['qty'],
            'price': line['price'], 'discount': line['discount'], 'tax': line['tax'],
            'line_total': line['line_total'],
          });
        }
        for (final payment in _payments) {
          await txn.insert('document_payments', {
            'document_type': 'sales', 'document_id': _saleId,
            'method': payment['method'], 'amount': payment['amount'],
            'reference': payment['reference'],
          });
        }
      });
      if (post) {
        await DatabaseHelper.instance.postSale(
          saleId: _saleId!, warehouseId: _warehouseId!, cashBoxId: _cashBoxId!,
          lines: _lines.map((line) => <String, num>{
            'product_id': line['product_id'] as int,
            'qty': line['qty'] as double,
            'factor': line['factor'] as double,
          }).toList(),
          net: _net, paid: _paid, customerId: _customerId,
        );
        setState(() => _status = 'مرحل');
        _message('تم حفظ وترحيل الفاتورة بنجاح');
      } else {
        setState(() => _status = 'مسودة');
        _message('تم حفظ مسودة الفاتورة');
      }
      await _loadInvoices();
    } catch (e) {
      _message('تعذر ${post ? 'ترحيل' : 'حفظ'} الفاتورة: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadInvoices() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query('sales_header', orderBy: 'id DESC', limit: 100);
      if (mounted) setState(() => _invoices = rows);
    } catch (e) { _message('تعذر تحميل الفواتير: $e'); }
  }

  Future<void> _openInvoiceList() async {
    await _loadInvoices();
    if (!mounted) return;
    final chosen = await showDialog<Map<String, Object?>>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('فتح فاتورة مبيعات'),
      content: SizedBox(width: 760, height: 420, child: _invoices.isEmpty
        ? const Center(child: Text('لا توجد فواتير'))
        : ListView.separated(itemCount: _invoices.length, separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (_, i) { final row = _invoices[i]; return ListTile(
            title: Text('${row['invoice_no'] ?? '—'}'),
            subtitle: Text('${row['invoice_date'] ?? ''} • ${row['status'] ?? ''} • ${_money(_v(row['net']))}'),
            onTap: () => Navigator.pop(ctx, row),
          ); })),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق'))],
    ));
    if (chosen != null) await _loadInvoice(chosen);
  }

  Future<void> _loadInvoice(Map<String, Object?> row) async {
    final id = (row['id'] as num).toInt();
    final db = await DatabaseHelper.instance.database;
    final lines = await db.rawQuery('''
      SELECT l.*, p.name, p.code, COALESCE(i.qty,0) AS stock
      FROM sales_lines l JOIN products p ON p.id=l.product_id
      LEFT JOIN inventory i ON i.product_id=p.id AND i.warehouse_id=?
      WHERE l.sales_id=? ORDER BY l.id
    ''', [row['warehouse_id'], id]);
    final payments = await db.query('document_payments',
      where: 'document_type=? AND document_id=?', whereArgs: ['sales', id], orderBy: 'id');
    if (!mounted) return;
    setState(() {
      _saleId = id; _invoiceNo.text = (row['invoice_no'] ?? '').toString();
      _date = DateTime.tryParse((row['invoice_date'] ?? '').toString()) ?? DateTime.now();
      _warehouseId = (row['warehouse_id'] as num?)?.toInt();
      _customerId = (row['customer_id'] as num?)?.toInt();
      _cashBoxId = (row['cash_box_id'] as num?)?.toInt();
      _paymentMethod = (row['payment_method'] ?? 'نقدي').toString();
      _notes.text = (row['notes'] ?? '').toString();
      _status = (row['status'] ?? 'مسودة').toString();
      _lines..clear()..addAll(lines.map((l) {
        final q = _v(l['qty']), p = _v(l['price']), d = _v(l['discount']), t = _v(l['tax']);
        return <String, Object?>{
          'product_id': (l['product_id'] as num).toInt(), 'name': l['name'],
          'code': l['code'], 'unit': l['unit'] ?? 'قطعة', 'qty': q,
          'factor': _v(l['factor']) == 0 ? 1.0 : _v(l['factor']), 'price': p,
          'discount': d, 'tax': t, 'gross': q*p, 'line_total': _v(l['line_total']),
          'stock': _v(l['stock']),
        };
      }));
      _payments..clear()..addAll(payments.map((p) => <String, Object?>{
        'method': p['method'], 'amount': _v(p['amount']), 'reference': p['reference'] ?? '',
      }));
      _editingLine = null; _products = []; _search.clear();
    });
    if (_status == 'مرحل') _message('هذه الفاتورة مرحلة؛ يمكنك عرضها فقط');
  }

  void _newInvoice() {
    setState(() {
      _saleId = null; _invoiceNo.text = _newInvoiceNo(); _date = DateTime.now();
      _customerId = null; _notes.clear(); _status = 'مسودة'; _paymentMethod = 'نقدي';
      _lines.clear(); _payments.clear(); _products.clear(); _search.clear();
      _qty.text = '1'; _price.clear(); _lineDiscount.text = '0'; _lineTax.text = '0';
      _editingLine = null;
    });
  }

  Future<void> _printPreview() async {
    await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('معاينة فاتورة المبيعات'),
      content: SizedBox(width: 620, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('رقم الفاتورة: ${_invoiceNo.text}'),
        Text('التاريخ: ${_dateString(_date)}'),
        const Divider(),
        ..._lines.map((l) => Text('${l['name']}  × ${_money(_v(l['qty']))}  = ${_money(_v(l['line_total']))}')),
        const Divider(),
        Text('الإجمالي: ${_money(_subtotal)}'),
        Text('الخصم: ${_money(_discount)}'),
        Text('الضريبة: ${_money(_tax)}'),
        Text('الصافي: ${_money(_net)}'),
        Text('المدفوع: ${_money(_paid)}'),
        Text('المتبقي: ${_money(_remaining)}'),
      ])),
      actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق'))],
    ));
  }

  Widget _field(String label, TextEditingController controller, {double width = 180, bool numeric = false}) =>
    SizedBox(width: width, child: TextField(controller: controller, keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true)));

  Widget _drop(String label, int? value, List<Map<String, Object?>> options, String textKey, ValueChanged<int?> onChanged) =>
    SizedBox(width: 210, child: DropdownButtonFormField<int>(
      value: options.any((r) => (r['id'] as num).toInt() == value) ? value : null,
      isExpanded: true, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
      items: options.map((r) => DropdownMenuItem<int>(value: (r['id'] as num).toInt(), child: Text('${r[textKey] ?? ''}', overflow: TextOverflow.ellipsis))).toList(),
      onChanged: _status == 'مرحل' ? null : onChanged));

  Widget _section(String title, Widget child, {Widget? trailing}) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))), if (trailing != null) trailing]),
      const SizedBox(height: 12), child,
    ])));

  @override
  void dispose() {
    _invoiceNo.dispose(); _notes.dispose(); _search.dispose(); _qty.dispose(); _price.dispose();
    _lineDiscount.dispose(); _lineTax.dispose(); _paymentAmount.dispose(); _paymentReference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locked = _status == 'مرحل';
    return Directionality(textDirection: TextDirection.rtl, child: _loading
      ? const Center(child: CircularProgressIndicator())
      : ListView(padding: const EdgeInsets.all(18), children: [
        Row(children: [
          const Expanded(child: Text('المبيعات', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold))),
          Chip(label: Text(_status), avatar: Icon(locked ? Icons.lock : Icons.edit_note, size: 18)),
          const SizedBox(width: 8),
          OutlinedButton.icon(onPressed: _openInvoiceList, icon: const Icon(Icons.folder_open), label: const Text('فتح')),
          const SizedBox(width: 8),
          OutlinedButton.icon(onPressed: _newInvoice, icon: const Icon(Icons.add), label: const Text('جديد')),
        ]),
        const SizedBox(height: 12),
        _section('رأس الفاتورة', Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          _field('رقم الفاتورة', _invoiceNo, width: 230),
          OutlinedButton.icon(onPressed: locked ? null : () async {
            final picked = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2000), lastDate: DateTime(2100));
            if (picked != null && mounted) setState(() => _date = picked);
          }, icon: const Icon(Icons.calendar_month), label: Text(_dateString(_date))),
          _drop('المخزن', _warehouseId, _warehouses, 'name', (v) => setState(() { _warehouseId = v; _products = []; })),
          _drop('العميل', _customerId, _customers, 'name', (v) => setState(() => _customerId = v)),
          _drop('جلسة / صندوق الكاشير', _cashBoxId, _cashBoxes, 'name', (v) => setState(() => _cashBoxId = v)),
          SizedBox(width: 190, child: DropdownButtonFormField<String>(
            value: _paymentMethod, decoration: const InputDecoration(labelText: 'طريقة الدفع', border: OutlineInputBorder(), isDense: true),
            items: const ['نقدي','آجل','جزئي','تحويل بنكي'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: locked ? null : (v) => setState(() => _paymentMethod = v ?? 'نقدي'))),
          _field('الكاشير', TextEditingController(text: 'المستخدم الحالي'), width: 190),
          SizedBox(width: 320, child: TextField(controller: _notes, enabled: !locked, decoration: const InputDecoration(labelText: 'ملاحظات الفاتورة', border: OutlineInputBorder(), isDense: true))),
        ])),
        _section('إضافة الأصناف', Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(width: 290, child: TextField(controller: _search, enabled: !locked, onSubmitted: (_) => _searchProducts(), decoration: const InputDecoration(labelText: 'الباركود / اسم الصنف / الكود', prefixIcon: Icon(Icons.search), border: OutlineInputBorder(), isDense: true))),
            OutlinedButton.icon(onPressed: locked ? null : _searchProducts, icon: const Icon(Icons.search), label: const Text('بحث')),
            _field('الكمية', _qty, numeric: true),
            _field('سعر البيع', _price, numeric: true),
            _field('الخصم', _lineDiscount, numeric: true),
            _field('الضريبة', _lineTax, numeric: true),
            FilledButton.icon(onPressed: locked ? null : _addOrUpdateLine, icon: Icon(_editingLine == null ? Icons.add_shopping_cart : Icons.save), label: Text(_editingLine == null ? 'إضافة / تحديث الصنف' : 'تحديث السطر')),
            OutlinedButton.icon(onPressed: locked ? null : () => setState(() { _search.clear(); _price.clear(); _qty.text='1'; _lineDiscount.text='0'; _lineTax.text='0'; _editingLine=null; _products=[]; }), icon: const Icon(Icons.clear), label: const Text('تفريغ الصنف')),
          ]),
          if (_products.isNotEmpty) ...[
            const SizedBox(height: 10), const Text('نتائج البحث (اختر صنفًا)'),
            Wrap(spacing: 8, runSpacing: 8, children: _products.map((p) => ActionChip(
              label: Text('${p['name']} • ${p['code'] ?? 'بلا كود'} • مخزون ${_money(_v(p['stock']))}'),
              onPressed: locked ? null : () => _chooseProduct(p))).toList()),
          ],
        ])),
        _section('سلة المبيعات', SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(
          columns: const [
            DataColumn(label: Text('#')), DataColumn(label: Text('الكود')), DataColumn(label: Text('الصنف')),
            DataColumn(label: Text('الوحدة')), DataColumn(label: Text('الكمية')), DataColumn(label: Text('السعر')),
            DataColumn(label: Text('الخصم')), DataColumn(label: Text('الضريبة')), DataColumn(label: Text('الإجمالي')),
            DataColumn(label: Text('إجراءات')),
          ],
          rows: List.generate(_lines.length, (i) { final l = _lines[i]; return DataRow(cells: [
            DataCell(Text('${i+1}')), DataCell(Text('${l['code'] ?? ''}')), DataCell(Text('${l['name'] ?? ''}')),
            DataCell(Text('${l['unit'] ?? ''}')), DataCell(Text(_money(_v(l['qty'])))),
            DataCell(Text(_money(_v(l['price'])))), DataCell(Text(_money(_v(l['discount'])))),
            DataCell(Text(_money(_v(l['tax'])))), DataCell(Text(_money(_v(l['line_total'])))),
            DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(tooltip: 'تعديل السطر', onPressed: locked ? null : () => _editLine(i), icon: const Icon(Icons.edit)),
              IconButton(tooltip: 'حذف السطر', onPressed: locked ? null : () => _removeLine(i), icon: const Icon(Icons.delete_outline, color: Colors.red)),
            ])),
          ]); }),
        ))),
        _section('المدفوعات', Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 10, runSpacing: 10, children: [
            SizedBox(width: 190, child: DropdownButtonFormField<String>(
              value: _paymentMethod, decoration: const InputDecoration(labelText: 'طريقة الدفعة', border: OutlineInputBorder(), isDense: true),
              items: const ['نقدي','بطاقة','تحويل بنكي','على الحساب'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: locked ? null : (v) => setState(() => _paymentMethod = v ?? 'نقدي'))),
            _field('مبلغ الدفعة', _paymentAmount, numeric: true),
            _field('المرجع', _paymentReference, width: 240),
            FilledButton.icon(onPressed: locked ? null : _addPayment, icon: const Icon(Icons.add), label: const Text('إضافة دفعة')),
          ]),
          const SizedBox(height: 8),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(
            columns: const [DataColumn(label: Text('طريقة الدفع')), DataColumn(label: Text('المبلغ')), DataColumn(label: Text('المرجع')), DataColumn(label: Text('إجراء'))],
            rows: List.generate(_payments.length, (i) { final p = _payments[i]; return DataRow(cells: [
              DataCell(Text('${p['method']}')), DataCell(Text(_money(_v(p['amount'])))),
              DataCell(Text('${p['reference'] ?? ''}')),
              DataCell(IconButton(tooltip: 'حذف الدفعة', onPressed: locked ? null : () => setState(() => _payments.removeAt(i)), icon: const Icon(Icons.delete_outline))),
            ]); }),
          )),
        ])),
        _section('ملخص الفاتورة', Wrap(spacing: 14, runSpacing: 12, children: [
          _summary('عدد السطور', '${_lines.length}'), _summary('الإجمالي قبل الخصم', _money(_subtotal)),
          _summary('الخصم', _money(_discount)), _summary('الضريبة', _money(_tax)),
          _summary('الصافي', _money(_net)), _summary('المدفوع', _money(_paid)),
          _summary('المتبقي', _money(_remaining)),
        ])),
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Wrap(spacing: 10, runSpacing: 10, children: [
          FilledButton.icon(onPressed: locked || _busy ? null : () => _save(post: false), icon: const Icon(Icons.save_outlined), label: const Text('حفظ مسودة')),
          FilledButton.icon(onPressed: locked || _busy ? null : () => _save(post: true), icon: const Icon(Icons.check_circle_outline), label: Text(_busy ? 'جارٍ الحفظ...' : 'حفظ وترحيل')),
          OutlinedButton.icon(onPressed: _printPreview, icon: const Icon(Icons.print_outlined), label: const Text('طباعة / معاينة')),
          OutlinedButton.icon(onPressed: _newInvoice, icon: const Icon(Icons.add), label: const Text('جديد')),
          OutlinedButton.icon(onPressed: () => Navigator.maybePop(context), icon: const Icon(Icons.close), label: const Text('إغلاق')),
        ]))),
      ]));
  }

  Widget _summary(String label, String value) => Container(
    width: 160, padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall), const SizedBox(height: 5),
      Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
    ]));
}
