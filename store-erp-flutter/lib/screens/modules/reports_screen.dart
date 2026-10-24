import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import '../../widgets/common_widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../data/database_helper.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override State<ReportsScreen> createState() => _ReportsScreenState();
}
class _ReportsScreenState extends State<ReportsScreen> {
  late Future<_ReportData> _future;
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  @override void initState() { super.initState(); _future = _load(); }
  Future<_ReportData> _load() async {
    final db = DatabaseHelper.instance;
    final sales = await db.query('sales_header', orderBy:'invoice_date DESC');
    final purchases = await db.query('purchases_header', orderBy:'invoice_date DESC');
    final inventory = await db.query('inventory');
    final products = await db.query('products');
    final customers = await db.query('customers');
    final suppliers = await db.query('suppliers');
    final entries = await db.query('accounting_entries', orderBy:'entry_date DESC');
    final lines = await db.query('accounting_entry_lines');
    return _ReportData(sales,purchases,inventory,products,customers,suppliers,entries,lines);
  }
  bool _within(Map<String,Object?> row, String key) {
    final value = DateTime.tryParse((row[key] ?? '').toString());
    if (value == null) return false;
    return !value.isBefore(DateTime(_from.year,_from.month,_from.day)) && !value.isAfter(DateTime(_to.year,_to.month,_to.day,23,59,59));
  }
  double _sum(List<Map<String,Object?>> rows,String key) => rows.fold<double>(0,(sum,row)=>sum+((row[key] as num?)?.toDouble() ?? 0));
  String _money(num n) => n.toStringAsFixed(2);
  CellValue _excelCell(Object? value) {
    if (value == null) return TextCellValue('');
    if (value is bool) return BoolCellValue(value);
    if (value is int) return IntCellValue(value);
    if (value is num) return DoubleCellValue(value.toDouble());
    return TextCellValue(value.toString());
  }

  Future<void> _export(List<Map<String,Object?>> rows, String name) async {
    if(rows.isEmpty) { _message('لا توجد بيانات لتصديرها'); return; }
    try {
      final headers = rows.first.keys.toList();
      final workbook = Excel.createExcel();
      final sheet = workbook['التقرير'];
      sheet.appendRow(headers.map(_excelCell).toList());
      for (final row in rows) {
        sheet.appendRow(headers.map((h) => _excelCell(row[h])).toList());
      }
      final bytes = workbook.encode();
      if (bytes == null) throw StateError('تعذر إنشاء ملف Excel');
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'StoreERP', 'exports'));
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, '${name}_${DateTime.now().millisecondsSinceEpoch}.xlsx'));
      await file.writeAsBytes(bytes, flush: true);
      _message('تم تصدير ملف Excel: ${file.path}');
    } catch(e) {_message('فشل التصدير: $e');}
  }
  void _message(String s) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s))); }
  Future<void> _pickDate(bool start) async {
    final initial=start?_from:_to;
    final picked=await showDatePicker(context:context,initialDate:initial,firstDate:DateTime(2000),lastDate:DateTime(2100));
    if(picked!=null) setState(() { if(start) _from=picked; else _to=picked; _future=_load(); });
  }
  Future<void> _showPrintPreview(
    List<Map<String, Object?>> sales,
    List<Map<String, Object?>> purchases,
    List<Map<String, Object?>> entries,
    double stockValue,
    double debit,
    double credit,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('معاينة طباعة التقارير العامة والمحاسبية'),
        content: SizedBox(
          width: 760,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('الفترة: ${_from.toIso8601String().substring(0, 10)} إلى ${_to.toIso8601String().substring(0, 10)}'),
                Text('صافي المبيعات: ${_money(_sum(sales, 'net'))}'),
                Text('صافي المشتريات: ${_money(_sum(purchases, 'net'))}'),
                Text('قيمة المخزون التقديرية: ${_money(stockValue)}'),
                Text('إجمالي المدين: ${_money(debit)} — إجمالي الدائن: ${_money(credit)}'),
                Text('فرق ميزان المراجعة: ${_money(debit - credit)}'),
                const Divider(height: 24),
                _previewTable('المبيعات', sales, const ['invoice_no', 'invoice_date', 'net', 'paid', 'status']),
                _previewTable('المشتريات', purchases, const ['invoice_no', 'invoice_date', 'net', 'paid', 'status']),
                _previewTable('القيود المحاسبية', entries, const ['entry_no', 'entry_date', 'source_type', 'description', 'status']),
                const Text('هذه معاينة للطباعة؛ لا يتم إرسالها إلى طابعة من هذه النافذة.', style: TextStyle(color: Colors.blueGrey)),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  Widget _previewTable(String title, List<Map<String, Object?>> rows, List<String> fields) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$title (${rows.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
          if (rows.isEmpty)
            const Text('لا توجد بيانات')
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: fields.map((field) => DataColumn(label: Text(field))).toList(),
                rows: rows.take(40).map((row) => DataRow(
                  cells: fields.map((field) => DataCell(Text((row[field] ?? '—').toString()))).toList(),
                )).toList(),
              ),
            ),
        ],
      ),
    );
  }

  @override Widget build(BuildContext context) => FutureBuilder<_ReportData>(future:_future,builder:(context,snapshot){
    if(snapshot.connectionState==ConnectionState.waiting) return const Center(child:CircularProgressIndicator());
    if(snapshot.hasError) return Center(child:Text('تعذر تحميل التقارير: ${snapshot.error}'));
    final d=snapshot.data!;
    final sales=d.sales.where((r)=>_within(r,'invoice_date')&&r['status']=='مرحل').toList();
    final purchases=d.purchases.where((r)=>_within(r,'invoice_date')&&r['status']=='مرحل').toList();
    final stockValue=d.inventory.fold<double>(0,(sum,row){final prod=d.products.where((x)=>x['id']==row['product_id']); final cost=prod.isEmpty?0.0:((prod.first['cost_price'] as num?)?.toDouble()??0);return sum+cost*((row['qty'] as num?)?.toDouble()??0);});
    final debit=_sum(d.journalLines,'debit'), credit=_sum(d.journalLines,'credit');
    return ListView(padding:const EdgeInsets.all(18),children:[
      Row(children: [
        const Expanded(child: Text('التقارير العامة والمحاسبية',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold))),
        OutlinedButton.icon(onPressed:()=>_showPrintPreview(sales,purchases,d.entries,stockValue,debit,credit),icon:const Icon(Icons.print_outlined),label:const Text('معاينة الطباعة')),
        const SizedBox(width:8),
        OutlinedButton.icon(onPressed:()=>closeModule(context),icon:const Icon(Icons.close),label:const Text('إغلاق')),
      ]),
      const SizedBox(height:12), Card(child:Padding(padding:const EdgeInsets.all(14),child:Wrap(spacing:10,runSpacing:10,crossAxisAlignment:WrapCrossAlignment.center,children:[OutlinedButton.icon(onPressed:()=>_pickDate(true),icon:const Icon(Icons.calendar_month),label:Text('من: ${_from.toIso8601String().substring(0,10)}')),OutlinedButton.icon(onPressed:()=>_pickDate(false),icon:const Icon(Icons.calendar_month),label:Text('إلى: ${_to.toIso8601String().substring(0,10)}')),FilledButton.tonalIcon(onPressed:()=>setState(()=>_future=_load()),icon:const Icon(Icons.refresh),label:const Text('تحديث'))]))),
      const SizedBox(height:8), Wrap(spacing:12,runSpacing:12,children:[_metric('صافي المبيعات',_money(_sum(sales,'net')),Icons.point_of_sale),_metric('صافي المشتريات',_money(_sum(purchases,'net')),Icons.shopping_cart),_metric('قيمة المخزون التقديرية',_money(stockValue),Icons.inventory_2),_metric('ذمم العملاء',_money(_sum(d.customers,'balance')),Icons.people),_metric('ذمم الموردين',_money(_sum(d.suppliers,'balance')),Icons.local_shipping),_metric('فرق ميزان المراجعة',_money(debit-credit),Icons.account_balance)]),
      const SizedBox(height:18),
      _section('ملخص المبيعات',sales,['id','invoice_no','invoice_date','net','paid','status'],'sales_report'),
      _section('ملخص المشتريات',purchases,['id','invoice_no','invoice_date','net','paid','status'],'purchases_report'),
      _section('القيود المحاسبية',d.entries,['id','entry_no','entry_date','source_type','source_id','description','status'],'journal_report'),
      Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('اختبار توازن القيود',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),const SizedBox(height:8),Text('إجمالي المدين: ${_money(debit)}'),Text('إجمالي الدائن: ${_money(credit)}'),Text((debit-credit).abs()<0.005?'القيود متوازنة إجمالًا':'تحذير: يوجد فرق في إجمالي القيود',style:TextStyle(color:(debit-credit).abs()<0.005?Colors.green:Colors.red,fontWeight:FontWeight.bold))]))),
    ]);
  });
  Widget _metric(String title,String value,IconData icon)=>SizedBox(width:MediaQuery.sizeOf(context).width>1200?250:MediaQuery.sizeOf(context).width*.42,child:Card(child:Padding(padding:const EdgeInsets.all(16),child:Row(children:[Icon(icon,size:28,color:const Color(0xFF059669)),const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(color:Colors.blueGrey)),const SizedBox(height:6),Text(value,style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold))]))]))));
  Widget _section(String title,List<Map<String,Object?>> rows,List<String> keys,String filename)=>Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[Expanded(child:Text('$title (${rows.length})',style:const TextStyle(fontSize:17,fontWeight:FontWeight.bold))),TextButton.icon(onPressed:()=>_export(rows,filename),icon:const Icon(Icons.download),label:const Text('تصدير Excel (.xlsx)'))]),const SizedBox(height:8),if(rows.isEmpty)const Padding(padding:EdgeInsets.all(12),child:Text('لا توجد بيانات ضمن الفترة'))else SingleChildScrollView(scrollDirection:Axis.horizontal,child:DataTable(columns:keys.map((k)=>DataColumn(label:Text(k))).toList(),rows:rows.take(100).map((r)=>DataRow(cells:keys.map((k)=>DataCell(Text((r[k]??'—').toString()))).toList())).toList()))])));
}
class _ReportData {
 final List<Map<String,Object?>> sales,purchases,inventory,products,customers,suppliers,entries,journalLines;
 const _ReportData(this.sales,this.purchases,this.inventory,this.products,this.customers,this.suppliers,this.entries,this.journalLines);
}
