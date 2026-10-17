import 'package:flutter/material.dart';
import '../../data/database_helper.dart';
import '../../widgets/common_widgets.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});
  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final db = DatabaseHelper.instance;
  final search = TextEditingController();
  final fields = {
    for (final f in ['name', 'code', 'phone', 'mobile', 'address', 'notes', 'credit_limit', 'balance', 'credit_notes'])
      f: TextEditingController()
  };
  List<Map<String, Object?>> customers = [];
  int? selectedId;
  String filter = '';
  bool active = true, suspended = false, managerApproval = false, busy = false, editing = true;

  @override
  void initState() { super.initState(); reload(); }

  @override
  void dispose() {
    search.dispose();
    for (final c in fields.values) { c.dispose(); }
    super.dispose();
  }

  void msg(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> reload() async {
    try {
      final rows = await db.query('customers', orderBy: 'name COLLATE NOCASE');
      if (mounted) setState(() => customers = rows);
    } catch (e) { msg('تعذر تحميل العملاء: $e'); }
  }

  void clearForm() {
    setState(() {
      selectedId = null;
      active = true; suspended = false; managerApproval = false; editing = true;
      for (final c in fields.values) { c.clear(); }
      fields['credit_limit']!.text = '0';
      fields['balance']!.text = '0';
    });
  }

  void selectCustomer(Map<String, Object?> row) {
    setState(() {
      selectedId = (row['id'] as num).toInt();
      for (final f in fields.keys) { fields[f]!.text = (row[f] ?? '').toString(); }
      active = ((row['is_active'] as num?)?.toInt() ?? 1) == 1;
      suspended = ((row['is_suspended'] as num?)?.toInt() ?? 0) == 1;
      managerApproval = ((row['manager_approval'] as num?)?.toInt() ?? 0) == 1;
      editing = false;
    });
  }

  Future<void> save() async {
    if (fields['name']!.text.trim().isEmpty) { msg('اسم العميل مطلوب'); return; }
    final limit = double.tryParse(fields['credit_limit']!.text.trim());
    if (limit == null || limit < 0) { msg('حد الدين يجب أن يكون رقمًا غير سالب'); return; }
    setState(() => busy = true);
    try {
      final data = <String, Object?>{
        'name': fields['name']!.text.trim(),
        'code': fields['code']!.text.trim().isEmpty ? null : fields['code']!.text.trim(),
        'phone': fields['phone']!.text.trim(),
        'mobile': fields['mobile']!.text.trim(),
        'address': fields['address']!.text.trim(),
        'notes': fields['notes']!.text.trim(),
        'credit_notes': fields['credit_notes']!.text.trim(),
        'credit_limit': limit,
        'is_active': active ? 1 : 0,
        'is_suspended': suspended ? 1 : 0,
        'manager_approval': managerApproval ? 1 : 0,
      };
      if (selectedId == null) {
        selectedId = await db.insert('customers', data);
        msg('تم إنشاء العميل');
      } else {
        await db.update('customers', data, where: 'id = ?', whereArgs: [selectedId]);
        msg('تم تحديث بيانات العميل');
      }
      await reload();
      final found = customers.where((r) => (r['id'] as num).toInt() == selectedId);
      if (found.isNotEmpty) selectCustomer(found.first);
    } catch (e) {
      msg('تعذر حفظ العميل: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> deleteCustomer() async {
    if (selectedId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('حذف العميل'),
        content: const Text('قد تمنع الفواتير والأرصدة المرتبطة حذف العميل.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await db.delete('customers', where: 'id = ?', whereArgs: [selectedId]);
      clearForm();
      await reload();
      msg('تم حذف العميل');
    } catch (e) { msg('لا يمكن حذف عميل مرتبط بفواتير أو أرصدة: $e'); }
  }

  @override
  Widget build(BuildContext context) {
    final visible = customers.where((row) =>
      filter.isEmpty || row.values.any((v) => v.toString().toLowerCase().contains(filter.toLowerCase()))
    ).toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          ActionButton('جديد', icon: Icons.add, onPressed: clearForm),
          ActionButton('حفظ', icon: Icons.save, primary: true, onPressed: busy ? () {} : save),
          ActionButton('تعديل', icon: Icons.edit, onPressed: () {
            if (selectedId == null) { msg('اختر عميلًا من القائمة أولًا'); }
            else { setState(() => editing = true); }
          }),
          ActionButton('تفريغ', icon: Icons.cleaning_services, onPressed: clearForm),
          ActionButton('تحديث', icon: Icons.refresh, onPressed: reload),
          ActionButton('حذف', icon: Icons.delete_outline, onPressed: deleteCustomer),
        ]),
        const SizedBox(height: 12),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: 390,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    TextField(
                      controller: search,
                      decoration: const InputDecoration(labelText: 'بحث عام عن العملاء', prefixIcon: Icon(Icons.search)),
                      onChanged: (v) => setState(() => filter = v.trim()),
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: OutlinedButton.icon(
                        onPressed: () => setState(() => filter = search.text.trim()),
                        icon: const Icon(Icons.search), label: const Text('بحث'),
                      )),
                      const SizedBox(width: 6),
                      IconButton(tooltip: 'تحديث', onPressed: reload, icon: const Icon(Icons.refresh)),
                    ]),
                    const Divider(),
                    Expanded(
                      child: visible.isEmpty
                        ? const Center(child: Text('لا توجد نتائج'))
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('الاسم')),
                                DataColumn(label: Text('الكود')),
                                DataColumn(label: Text('الجوال')),
                                DataColumn(label: Text('الرصيد')),
                                DataColumn(label: Text('الحالة')),
                              ],
                              rows: visible.map((row) => DataRow(
                                selected: (row['id'] as num).toInt() == selectedId,
                                onSelectChanged: (_) => selectCustomer(row),
                                cells: [
                                  DataCell(Text((row['name'] ?? '').toString())),
                                  DataCell(Text((row['code'] ?? '—').toString())),
                                  DataCell(Text((row['mobile'] ?? '—').toString())),
                                  DataCell(Text((row['balance'] ?? 0).toString())),
                                  DataCell(Text(((row['is_active'] as num?)?.toInt() ?? 1) == 1 ? 'نشط' : 'غير نشط')),
                                ],
                              )).toList(),
                            ),
                          ),
                    ),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Card(
                child: ListView(
                  padding: const EdgeInsets.all(18),
                  children: [
                    Text(
                      selectedId == null ? 'بيانات عميل جديد' : 'بيانات العميل #$selectedId',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    Wrap(spacing: 12, runSpacing: 12, children: [
                      for (final entry in fields.entries)
                        SizedBox(
                          width: ['address', 'notes', 'credit_notes'].contains(entry.key) ? 500 : 240,
                          child: TextField(
                            controller: entry.value,
                            readOnly: entry.key == 'balance' || !editing,
                            keyboardType: entry.key == 'credit_limit' || entry.key == 'balance'
                              ? const TextInputType.numberWithOptions(decimal: true)
                              : TextInputType.text,
                            maxLines: ['address', 'notes', 'credit_notes'].contains(entry.key) ? 2 : 1,
                            decoration: InputDecoration(labelText: switch (entry.key) {
                              'name' => 'اسم العميل *',
                              'code' => 'كود العميل',
                              'phone' => 'الهاتف',
                              'mobile' => 'الجوال',
                              'address' => 'العنوان',
                              'notes' => 'ملاحظات',
                              'credit_limit' => 'حد الدين / الائتمان',
                              'credit_notes' => 'ملاحظات ائتمانية',
                              'balance' => 'الرصيد الحالي (يُحدّث من الحركات)',
                              _ => entry.key,
                            }),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 16),
                    const Divider(),
                    Text('البيانات الائتمانية والتحكم', style: Theme.of(context).textTheme.titleMedium),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('حساب نشط'),
                      subtitle: const Text('يمكن اختيار العميل في الفواتير'),
                      value: active,
                      onChanged: editing ? (v) => setState(() => active = v) : null,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('إيقاف التعامل الائتماني'),
                      subtitle: const Text('يمنع البيع الآجل للعميل عند الترحيل'),
                      value: suspended,
                      onChanged: editing ? (v) => setState(() => suspended = v) : null,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('موافقة المدير'),
                      subtitle: const Text('تسجيل الموافقة الإدارية على حساب العميل'),
                      value: managerApproval,
                      onChanged: editing ? (v) => setState(() => managerApproval = v) : null,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'الرصيد الحالي للعرض فقط، ويُحدّث من فواتير البيع والتحصيلات؛ لا يُعدّل يدويًا من بطاقة العميل.',
                      style: TextStyle(color: Colors.blueGrey),
                    ),
                  ],
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
