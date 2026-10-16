import 'package:flutter/material.dart';
import '../../data/database_helper.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> with SingleTickerProviderStateMixin {
  final db = DatabaseHelper.instance;
  final search = TextEditingController();
  late final TabController tabs;
  List<Map<String,Object?>> products = [], warehouses = [], categories = [], inventory = [], batches = [], reorder = [];
  int? warehouseId, categoryId;
  String filter = '';
  bool loading = false;

  @override
  void initState() { super.initState(); tabs = TabController(length: 4, vsync: this); reload(); }
  @override
  void dispose() { tabs.dispose(); search.dispose(); super.dispose(); }
  void msg(String value) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value))); }
  double numv(Object? value) => (value as num?)?.toDouble() ?? 0;
  String money(Object? value) => numv(value).toStringAsFixed(2);
  Map<String,Object?>? product(Object? id) { for (final p in products) { if ((p['id'] as num?)?.toInt() == (id as num?)?.toInt()) return p; } return null; }
  Map<String,Object?>? warehouse(Object? id) { for (final w in warehouses) { if ((w['id'] as num?)?.toInt() == (id as num?)?.toInt()) return w; } return null; }
  Map<String,Object?>? category(Object? id) { for (final c in categories) { if ((c['id'] as num?)?.toInt() == (id as num?)?.toInt()) return c; } return null; }

  Future<void> reload() async {
    setState(() => loading = true);
    try {
      final results = await Future.wait([
        db.query('products', orderBy: 'name'), db.query('warehouses', orderBy: 'name'),
        db.query('categories', orderBy: 'name'), db.query('inventory'),
        db.query('product_batches', orderBy: 'expiry_date'), db.query('reorder_levels'),
      ]);
      if (!mounted) return;
      setState(() { products=results[0]; warehouses=results[1]; categories=results[2]; inventory=results[3]; batches=results[4]; reorder=results[5]; });
    } catch (e) { msg('تعذر تحديث المخزون: $e'); }
    finally { if (mounted) setState(() => loading = false); }
  }

  bool matches(Map<String,Object?> row, {bool batch = false}) {
    if (warehouseId != null && (row['warehouse_id'] as num?)?.toInt() != warehouseId) return false;
    final p = product(row['product_id']);
    if (p == null) return false;
    if (categoryId != null && (p['category_id'] as num?)?.toInt() != categoryId) return false;
    if (filter.isEmpty) return true;
    return [p['name'],p['code'],p['english_name'],row['batch_no'],row['expiry_date'],warehouse(row['warehouse_id'])?['name']]
        .join(' ').toLowerCase().contains(filter.toLowerCase());
  }

  List<Map<String,Object?>> get stockRows => inventory.where((r) => matches(r)).toList();
  List<Map<String,Object?>> get lowRows => stockRows.where((r) {
    final level = reorder.where((x) => x['product_id']==r['product_id'] && x['warehouse_id']==r['warehouse_id']);
    final minimum = level.isEmpty ? 0.0 : numv(level.first['minimum']);
    return numv(r['qty']) <= minimum;
  }).toList();
  List<Map<String,Object?>> get expiredRows => batches.where((r) => matches(r,batch:true) && DateTime.tryParse((r['expiry_date']??'').toString())?.isBefore(DateTime.now()) == true).toList();
  List<Map<String,Object?>> get expiringRows => batches.where((r) {
    if (!matches(r,batch:true)) return false;
    final d=DateTime.tryParse((r['expiry_date']??'').toString());
    return d!=null && !d.isBefore(DateTime.now()) && d.isBefore(DateTime.now().add(const Duration(days:31)));
  }).toList();
  double get stockValue => stockRows.fold(0.0,(sum,r)=>sum+numv(r['qty'])*numv(product(r['product_id'])?['cost_price']));
  double get expiredQty => expiredRows.fold(0.0,(sum,r)=>sum+numv(r['qty']));
  double get expiringQty => expiringRows.fold(0.0,(sum,r)=>sum+numv(r['qty']));

  Widget metric(String title,String value,IconData icon) => SizedBox(width:220,child:Card(child:ListTile(leading:Icon(icon),title:Text(title),subtitle:Text(value,style:const TextStyle(fontSize:19,fontWeight:FontWeight.bold)))));
  @override
  Widget build(BuildContext context) => ListView(padding:const EdgeInsets.all(18),children:[
    Row(children:[const Expanded(child:Text('إدارة المخزون',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold))),OutlinedButton.icon(onPressed:loading?null:reload,icon:const Icon(Icons.refresh),label:const Text('تحديث')),const SizedBox(width:8),OutlinedButton.icon(onPressed:()=>showPrintPreview(),icon:const Icon(Icons.print_outlined),label:const Text('طباعة / معاينة'))]),
    const SizedBox(height:12),
    Card(child:Padding(padding:const EdgeInsets.all(14),child:Wrap(spacing:12,runSpacing:12,children:[
      SizedBox(width:240,child:DropdownButtonFormField<int>(value:warehouseId,decoration:const InputDecoration(labelText:'المخزن'),items:[const DropdownMenuItem<int>(value:null,child:Text('كل المخازن')),...warehouses.map((w)=>DropdownMenuItem(value:(w['id'] as num).toInt(),child:Text('${w['name']}')))],onChanged:(v)=>setState(()=>warehouseId=v))),
      SizedBox(width:240,child:DropdownButtonFormField<int>(value:categoryId,decoration:const InputDecoration(labelText:'القسم'),items:[const DropdownMenuItem<int>(value:null,child:Text('كل الأقسام')),...categories.map((c)=>DropdownMenuItem(value:(c['id'] as num).toInt(),child:Text('${c['name']}')))],onChanged:(v)=>setState(()=>categoryId=v))),
      SizedBox(width:300,child:TextField(controller:search,decoration:const InputDecoration(labelText:'بحث بالاسم أو الكود أو الدفعة',prefixIcon:Icon(Icons.search)),onChanged:(v)=>setState(()=>filter=v.trim()))),
      OutlinedButton(onPressed:()=>setState(()=>{filter='',warehouseId=null,categoryId=null,search.clear()}),child:const Text('مسح الفلاتر')),
    ]))),
    Wrap(spacing:8,runSpacing:8,children:[
      metric('إجمالي قيمة المخزون',money(stockValue),Icons.payments_outlined),
      metric('أصناف قرب النفاد','${lowRows.length}',Icons.warning_amber_outlined),
      metric('كمية الدفعات المنتهية',money(expiredQty),Icons.event_busy_outlined),
      metric('كمية قرب الانتهاء',money(expiringQty),Icons.hourglass_bottom_outlined),
    ]),
    if(loading) const LinearProgressIndicator(),
    Card(child:Column(children:[
      TabBar(controller:tabs,isScrollable:true,tabs:const[Tab(text:'رصيد المخزون'),Tab(text:'قرب النفاد'),Tab(text:'منتهي الصلاحية'),Tab(text:'قرب الانتهاء')]),
      SizedBox(height:500,child:TabBarView(controller:tabs,children:[
        table(stockRows,false),table(lowRows,false),table(expiredRows,true),table(expiringRows,true),
      ])),
    ])),
    const Padding(padding:EdgeInsets.only(top:8),child:Text('الأرصدة للعرض فقط وتتغير من المستندات المرحلة. يمكن تصدير الجداول لاحقًا كملف Excel أصلي؛ الطباعة الحالية معاينة داخل التطبيق.',style:TextStyle(color:Colors.blueGrey))),
  ]);

  Widget table(List<Map<String,Object?>> rows,bool withBatch) {
    if(rows.isEmpty)return const Center(child:Text('لا توجد بيانات مطابقة.'));
    final headers=withBatch?const['الصنف','الكود','المخزن','الدفعة','الكمية','الانتهاء']:const['الصنف','الكود','القسم','المخزن','الرصيد','التكلفة','القيمة'];
    return SingleChildScrollView(scrollDirection:Axis.horizontal,child:SingleChildScrollView(child:DataTable(columns:headers.map((h)=>DataColumn(label:Text(h))).toList(),rows:rows.map((r){
      final p=product(r['product_id']);final qty=numv(r['qty']);final cost=numv(p?['cost_price']);
      final values=withBatch?[p?['name']??'—',p?['code']??'—',warehouse(r['warehouse_id'])?['name']??'—',r['batch_no']??'—',money(qty),r['expiry_date']??'—']:[p?['name']??'—',p?['code']??'—',category(p?['category_id'])?['name']??'—',warehouse(r['warehouse_id'])?['name']??'—',money(qty),money(cost),money(qty*cost)];
      return DataRow(cells:values.map((v)=>DataCell(Text(v.toString()))).toList());
    }).toList())));
  }

  Future<void> showPrintPreview() async {
    final rows=switch(tabs.index){1=>lowRows,2=>expiredRows,3=>expiringRows,_=>stockRows};
    final title=switch(tabs.index){1=>'قرب النفاد',2=>'منتهي الصلاحية',3=>'قرب الانتهاء',_=>'رصيد المخزون'};
    await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(title:Text('معاينة طباعة — $title'),content:SizedBox(width:620,child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('عدد السجلات: ${rows.length}'),Text('القيمة التقديرية للمخزون: ${money(stockValue)}'),const Divider(),...rows.take(80).map((r)=>Text('${product(r['product_id'])?['name']??'صنف'} | ${warehouse(r['warehouse_id'])?['name']??'—'} | كمية: ${r['qty']??0} | انتهاء: ${r['expiry_date']??'—'}'))]))),actions:[FilledButton(onPressed:()=>Navigator.pop(ctx),child:const Text('إغلاق'))]));
  }
}
