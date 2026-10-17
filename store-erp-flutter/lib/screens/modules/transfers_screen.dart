import 'package:flutter/material.dart';
import '../../data/database_helper.dart';

class WarehouseTransfersScreen extends StatefulWidget {
  const WarehouseTransfersScreen({super.key});
  @override
  State<WarehouseTransfersScreen> createState() => _WarehouseTransfersScreenState();
}

class _WarehouseTransfersScreenState extends State<WarehouseTransfersScreen> {
  final db = DatabaseHelper.instance;
  final number = TextEditingController();
  final notes = TextEditingController();
  final search = TextEditingController();
  final qty = TextEditingController(text: '1');
  List<Map<String,Object?>> warehouses=[], products=[], units=[], docs=[], lines=[];
  int? fromId, toId, productId, unitId, transferId, selectedLineId;
  DateTime date = DateTime.now();
  String status='مسودة';
  bool busy=false;
  String dateText(DateTime d)=>d.toIso8601String().substring(0,10);
  double n(Object? v)=>(v as num?)?.toDouble()??0;
  void msg(String s){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));}

  @override
  void initState(){super.initState();_load();}
  @override
  void dispose(){number.dispose();notes.dispose();search.dispose();qty.dispose();super.dispose();}

  Future<void> _load() async {
    try {
      final w=await db.query('warehouses',where:'is_active=1',orderBy:'name');
      final p=await db.query('products',where:'is_active=1',orderBy:'name');
      final d=await db.query('warehouse_transfers',orderBy:'transfer_date DESC',limit:300);
      if(!mounted)return;
      setState(()=>{warehouses=w,products=p,docs=d,fromId??=(w.isEmpty?null:(w.first['id'] as num).toInt()),toId??=(w.length<2?null:(w[1]['id'] as num).toInt())});
    }catch(e){msg('تعذر تحميل التحويلات: $e');}
  }

  Future<void> _loadUnits() async {
    if(productId==null){if(mounted)setState(()=>units=[]);return;}
    final rows=await db.query('product_units',where:'product_id=?',whereArgs:[productId],orderBy:'factor');
    if(mounted)setState(()=>{units=rows,unitId=rows.isEmpty?null:(rows.first['id'] as num).toInt()});
  }

  Future<void> _new() async {
    if(warehouses.length<2){msg('يلزم وجود مخزنين نشطين على الأقل');return;}
    final id=await db.insert('warehouse_transfers',{'transfer_no':'TR-${DateTime.now().microsecondsSinceEpoch}','transfer_date':dateText(date),'from_warehouse_id':fromId,'to_warehouse_id':toId,'status':'مسودة','notes':notes.text.trim()});
    if(!mounted)return;
    setState(()=>{transferId=id,number.text='TR-$id',status='مسودة',lines=[],selectedLineId=null,notes.text=''});
    await _reloadDocs();msg('تم إنشاء مسودة التحويل');
  }

  Future<void> _reloadDocs() async {
    final d=await db.query('warehouse_transfers',orderBy:'transfer_date DESC',limit:300);
    if(mounted)setState(()=>docs=d);
  }

  Future<void> _open(Map<String,Object?> d) async {
    final id=(d['id'] as num).toInt();
    final l=await db.query('warehouse_transfer_lines',where:'transfer_id=?',whereArgs:[id],orderBy:'id');
    if(!mounted)return;
    setState(()=>{transferId=id,number.text=(d['transfer_no']??'').toString(),date=DateTime.tryParse((d['transfer_date']??'').toString())??DateTime.now(),fromId=(d['from_warehouse_id'] as num?)?.toInt(),toId=(d['to_warehouse_id'] as num?)?.toInt(),status=(d['status']??'مسودة').toString(),notes.text=(d['notes']??'').toString(),lines=l,selectedLineId=null});
  }

  Future<void> _addLine() async {
    if(transferId==null){msg('أنشئ مستند تحويل أولًا');return;}
    if(status!='مسودة'){msg('لا يمكن تعديل تحويل غير مسودة');return;}
    if(productId==null){msg('اختر الصنف');return;}
    final amount=double.tryParse(qty.text)??0;
    if(amount<=0){msg('الكمية يجب أن تكون أكبر من صفر');return;}
    final unit=units.where((u)=>(u['id'] as num).toInt()==unitId).firstOrNull;
    final factor=n(unit?['factor'])>0?n(unit?['factor']):1;
    final unitName=(unit?['unit_name']??'قطعة').toString();
    await db.insert('warehouse_transfer_lines',{'transfer_id':transferId,'product_id':productId,'qty':amount,'factor':factor,'unit':unitName});
    final l=await db.query('warehouse_transfer_lines',where:'transfer_id=?',whereArgs:[transferId],orderBy:'id');
    if(mounted)setState(()=>{lines=l,qty.text='1',selectedLineId=null});
  }

  Future<void> _removeLine() async {
    if(status!='مسودة'||selectedLineId==null){msg('حدد سطرًا من مسودة');return;}
    await db.delete('warehouse_transfer_lines',where:'id=? AND transfer_id=?',whereArgs:[selectedLineId,transferId]);
    if(mounted)setState(()=>{lines.removeWhere((l)=>l['id']==selectedLineId),selectedLineId=null});
  }

  Future<void> _save() async {
    if(transferId==null){msg('أنشئ مستند تحويل أولًا');return;}
    if(status!='مسودة'){msg('التحويل غير قابل للتعديل');return;}
    if(fromId==null||toId==null||fromId==toId){msg('اختر مخزنين مختلفين');return;}
    try{
      await db.update('warehouse_transfers',{'transfer_no':number.text.trim(),'transfer_date':dateText(date),'from_warehouse_id':fromId,'to_warehouse_id':toId,'notes':notes.text.trim()},where:'id=?',whereArgs:[transferId]);
      await _reloadDocs();msg('تم حفظ مسودة التحويل');
    }catch(e){msg('تعذر حفظ التحويل: $e');}
  }

  Future<void> _post() async {
    if(transferId==null||lines.isEmpty){msg('أنشئ التحويل وأضف الأصناف أولًا');return;}
    if(status!='مسودة'){msg('التحويل مرحل أو غير قابل للترحيل');return;}
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('تأكيد ترحيل التحويل'),content:const Text('سيتم خصم الكميات من المخزن المصدر وإضافتها إلى المخزن المستلم.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('ترحيل'))]));
    if(ok!=true||!mounted)return;
    setState(()=>busy=true);
    try{
      await _save();
      await db.transferWarehouse(transferId:transferId!,lines:lines.map((l)=><String,num>{'product_id':l['product_id'] as num,'qty':l['qty'] as num,'factor':l['factor'] as num? ?? 1}).toList());
      if(mounted)setState(()=>status='مرحل');
      await _reloadDocs();msg('تم ترحيل التحويل وتحديث المخزون');
    }catch(e){msg('تعذر ترحيل التحويل: $e');}
    finally{if(mounted)setState(()=>busy=false);}
  }

  Future<void> _pickDate() async {
    final d=await showDatePicker(context:context,initialDate:date,firstDate:DateTime(2000),lastDate:DateTime(2100));
    if(d!=null&&mounted)setState(()=>date=d);
  }

  @override
  Widget build(BuildContext context){
    final q=search.text.trim().toLowerCase();
    final matches=products.where((p)=>q.isEmpty||(p['name']??'').toString().toLowerCase().contains(q)||(p['code']??'').toString().toLowerCase().contains(q)).take(50).toList();
    final from=warehouses.where((w)=>(w['id'] as num).toInt()==fromId).firstOrNull;
    final to=warehouses.where((w)=>(w['id'] as num).toInt()==toId).firstOrNull;
    return ListView(padding:const EdgeInsets.all(18),children:[
      Row(children:[const Expanded(child:Text('تحويل المخازن',style:TextStyle(fontSize:25,fontWeight:FontWeight.bold))),Chip(label:Text(status)),OutlinedButton.icon(onPressed:busy?null:_reloadDocs,icon:const Icon(Icons.refresh),label:const Text('تحديث سجل التحويلات'))]),
      Card(child:Padding(padding:const EdgeInsets.all(14),child:Wrap(spacing:12,runSpacing:12,crossAxisAlignment:WrapCrossAlignment.center,children:[
        SizedBox(width:200,child:TextField(controller:number,decoration:const InputDecoration(labelText:'رقم التحويل',border:OutlineInputBorder()))),
        SizedBox(width:230,child:DropdownButtonFormField<int>(value:warehouses.any((w)=>(w['id'] as num).toInt()==fromId)?fromId:null,decoration:const InputDecoration(labelText:'المخزن المصدر',border:OutlineInputBorder()),items:warehouses.map((w)=>DropdownMenuItem(value:(w['id'] as num).toInt(),child:Text((w['name']??'').toString()))).toList(),onChanged:status=='مسودة'?(v)=>setState(()=>fromId=v):null)),
        SizedBox(width:230,child:DropdownButtonFormField<int>(value:warehouses.any((w)=>(w['id'] as num).toInt()==toId)?toId:null,decoration:const InputDecoration(labelText:'المخزن المستلم',border:OutlineInputBorder()),items:warehouses.where((w)=>(w['id'] as num).toInt()!=fromId).map((w)=>DropdownMenuItem(value:(w['id'] as num).toInt(),child:Text((w['name']??'').toString()))).toList(),onChanged:status=='مسودة'?(v)=>setState(()=>toId=v):null)),
        OutlinedButton.icon(onPressed:_pickDate,icon:const Icon(Icons.calendar_month),label:Text(dateText(date))),
        SizedBox(width:360,child:TextField(controller:notes,decoration:const InputDecoration(labelText:'السبب / الملاحظات',border:OutlineInputBorder()))),
        OutlinedButton.icon(onPressed:busy?null:_new,icon:const Icon(Icons.add),label:const Text('جديد')),
        OutlinedButton.icon(onPressed:busy?null:_save,icon:const Icon(Icons.save_outlined),label:const Text('حفظ')),
      ]))),
      Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Text('إضافة الأصناف',style:Theme.of(context).textTheme.titleMedium),const SizedBox(height:10),
        TextField(controller:search,decoration:const InputDecoration(labelText:'بحث بالاسم أو الكود أو الباركود',prefixIcon:Icon(Icons.search),border:OutlineInputBorder()),onChanged:(_)=>setState((){})),
        const SizedBox(height:10),
        Wrap(spacing:12,runSpacing:12,children:[
          SizedBox(width:300,child:DropdownButtonFormField<int>(value:products.any((p)=>(p['id'] as num).toInt()==productId)?productId:null,decoration:const InputDecoration(labelText:'الصنف المختار',border:OutlineInputBorder()),items:matches.map((p)=>DropdownMenuItem(value:(p['id'] as num).toInt(),child:Text('${p['name']} • ${p['code']??''}',overflow:TextOverflow.ellipsis))).toList(),onChanged:status=='مسودة'?(v){setState(()=>productId=v);_loadUnits();}:null)),
          SizedBox(width:220,child:DropdownButtonFormField<int?>(value:unitId,decoration:const InputDecoration(labelText:'الوحدة',border:OutlineInputBorder()),items:[const DropdownMenuItem<int?>(value:null,child:Text('الوحدة الأساسية')),...units.map((u)=>DropdownMenuItem<int?>(value:(u['id'] as num).toInt(),child:Text('${u['unit_name']} × ${u['factor']}')))],onChanged:(v)=>setState(()=>unitId=v))),
          SizedBox(width:130,child:TextField(controller:qty,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'الكمية',border:OutlineInputBorder()))),
          FilledButton.icon(onPressed:busy?null:_addLine,icon:const Icon(Icons.add),label:const Text('إضافة صنف')),
          OutlinedButton.icon(onPressed:busy?null:_removeLine,icon:const Icon(Icons.delete_outline),label:const Text('حذف سطر')),
        ]),
        if(from!=null&&to!=null) Padding(padding:const EdgeInsets.only(top:10),child:Text('من ${from['name']} إلى ${to['name']}')),
      ]))),
      Card(child:Padding(padding:const EdgeInsets.all(10),child:SingleChildScrollView(scrollDirection:Axis.horizontal,child:DataTable(columns:const[
        DataColumn(label:Text('تحديد')),DataColumn(label:Text('الصنف')),DataColumn(label:Text('الكمية')),DataColumn(label:Text('الوحدة')),DataColumn(label:Text('معامل التحويل')),
      ],rows:lines.map((l){
        final p=products.where((p)=>(p['id'] as num).toInt()==(l['product_id'] as num).toInt()).firstOrNull;
        final selected=selectedLineId==(l['id'] as num).toInt();
        return DataRow(selected:selected,onSelectChanged:(_)=>setState(()=>selectedLineId=(l['id'] as num).toInt()),cells:[
          DataCell(Checkbox(value:selected,onChanged:(_)=>setState(()=>selectedLineId=(l['id'] as num).toInt()))),
          DataCell(Text((p?['name']??l['product_id']).toString())),DataCell(Text(n(l['qty']).toStringAsFixed(2))),
          DataCell(Text((l['unit']??'قطعة').toString())),DataCell(Text(n(l['factor']).toStringAsFixed(2))),
        ]);
      }).toList())))),
      Card(child:Padding(padding:const EdgeInsets.all(12),child:Wrap(spacing:10,runSpacing:8,children:[
        FilledButton.icon(onPressed:busy?null:_post,icon:const Icon(Icons.publish),label:const Text('حفظ وترحيل')),
        OutlinedButton.icon(onPressed:busy?null:_reload,icon:const Icon(Icons.refresh),label:const Text('تحديث')),
        OutlinedButton.icon(onPressed:()=>showDialog<void>(context:context,builder:(ctx)=>AlertDialog(title:const Text('سجل التحويلات'),content:SizedBox(width:700,child:ListView(shrinkWrap:true,children:docs.map((d)=>ListTile(title:Text((d['transfer_no']??'').toString()),subtitle:Text('${d['transfer_date']} • ${d['status']}'),onTap:(){Navigator.pop(ctx);_open(d);})).toList())),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('إغلاق'))])),icon:const Icon(Icons.list_alt),label:const Text('سجل التحويلات')),
        OutlinedButton.icon(onPressed:()=>Navigator.maybePop(context),icon:const Icon(Icons.close),label:const Text('إغلاق')),
      ]))),
      if(busy)const LinearProgressIndicator(),
    ]);
  }
}
