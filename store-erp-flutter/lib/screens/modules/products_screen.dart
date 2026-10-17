import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import '../../data/database_helper.dart';
import '../../widgets/common_widgets.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});
  @override State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> with SingleTickerProviderStateMixin {
  final db = DatabaseHelper.instance;
  final search = TextEditingController();
  final code = TextEditingController(), name = TextEditingController(), englishName = TextEditingController();
  final unit = TextEditingController(text: 'قطعة'), cost = TextEditingController(text: '0'), price = TextEditingController(text: '0'), notes = TextEditingController(), expiryWarningDays = TextEditingController(text: '30');
  late final TabController tabs;
  List<Map<String,Object?>> products=[], categories=[], warehouses=[], cashBoxes=[], units=[], barcodes=[], reorderLevels=[], batches=[], stock=[];
  int? selectedId, categoryId, subcategoryId, defaultCashBoxId;
  String filter='', saleMethod='قطعة', itemType='مخزني', pricingMode='ثابت';
  bool tracking=true, weighted=false, active=true, negativeStock=false, expiryTracking=false, batchTracking=false, returnable=true, visibleToEmployee=true, requiresManagerApproval=false, busy=false;

  @override void initState(){super.initState(); tabs=TabController(length:5,vsync:this); reload();}
  @override void dispose(){tabs.dispose();search.dispose();code.dispose();name.dispose();englishName.dispose();unit.dispose();cost.dispose();price.dispose();notes.dispose();expiryWarningDays.dispose();super.dispose();}
  void msg(String value){if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(value)));}

  Future<void> reload() async {
    try {
      final result=await Future.wait([db.query('products',orderBy:'name COLLATE NOCASE'),db.query('categories',orderBy:'name'),db.query('warehouses',orderBy:'name'),db.query('cash_boxes',where:'is_active=1',orderBy:'name')]);
      if(!mounted)return;
      setState(() { products=result[0]; categories=result[1]; warehouses=result[2]; cashBoxes=result[3]; });
      if(selectedId!=null) await loadChildren();
    } catch(e) {msg('تعذر تحميل الأصناف: $e');}
  }
  Future<void> loadChildren() async {
    final id=selectedId; if(id==null)return;
    try {
      final r=await Future.wait([
        db.query('product_units',where:'product_id=?',whereArgs:[id]),
        db.query('barcodes',where:'product_id=?',whereArgs:[id]),
        db.query('reorder_levels',where:'product_id=?',whereArgs:[id]),
        db.query('product_batches',where:'product_id=?',whereArgs:[id],orderBy:'expiry_date'),
        db.query('inventory',where:'product_id=?',whereArgs:[id]),
      ]);
      if(!mounted)return;
      setState(() { units=r[0]; barcodes=r[1]; reorderLevels=r[2]; batches=r[3]; stock=r[4]; });
    } catch(e) {msg('تعذر تحميل تفاصيل الصنف: $e');}
  }
  void clearForm(){
    setState((){
      selectedId=null;categoryId=null;subcategoryId=null;defaultCashBoxId=null;saleMethod='قطعة';itemType='مخزني';pricingMode='ثابت';tracking=true;weighted=false;active=true;negativeStock=false;expiryTracking=false;batchTracking=false;returnable=true;visibleToEmployee=true;requiresManagerApproval=false;expiryWarningDays.text='30';
      code.clear();name.clear();englishName.clear();unit.text='قطعة';cost.text='0';price.text='0';notes.clear();
      units=[];barcodes=[];reorderLevels=[];batches=[];stock=[];
    });
    tabs.animateTo(0);
  }
  void selectProduct(Map<String,Object?> p){
    setState((){
      selectedId=(p['id'] as num).toInt();code.text=(p['code']??'').toString();name.text=(p['name']??'').toString();
      englishName.text=(p['english_name']??'').toString();categoryId=(p['category_id'] as num?)?.toInt();
      unit.text=(p['unit']??'قطعة').toString();saleMethod=(p['sale_method']??'قطعة').toString();
      subcategoryId=(p['subcategory_id'] as num?)?.toInt(); defaultCashBoxId=(p['default_cash_box_id'] as num?)?.toInt();
      itemType=(p['item_type']??'مخزني').toString(); pricingMode=(p['pricing_mode']??'ثابت').toString();
      expiryTracking=((p['expiry_tracking'] as num?)?.toInt()??0)==1; batchTracking=((p['batch_tracking'] as num?)?.toInt()??0)==1;
      returnable=((p['is_returnable'] as num?)?.toInt()??1)==1; visibleToEmployee=((p['visible_to_employee'] as num?)?.toInt()??1)==1; requiresManagerApproval=((p['requires_manager_approval'] as num?)?.toInt()??0)==1;
      expiryWarningDays.text=((p['expiry_warning_days'] as num?)?.toInt()??30).toString();
      cost.text=((p['cost_price'] as num?)??0).toString();price.text=((p['sale_price'] as num?)??0).toString();notes.text=(p['notes']??'').toString();
      tracking=((p['stock_tracking'] as num?)?.toInt()??1)==1;negativeStock=((p['negative_stock'] as num?)?.toInt()??0)==1;
      active=((p['is_active'] as num?)?.toInt()??1)==1;weighted=saleMethod=='وزن';
    });
    loadChildren();
  }
  Future<void> saveProduct() async {
    if(name.text.trim().isEmpty){msg('اسم الصنف مطلوب');return;}
    final c=double.tryParse(cost.text.trim()),p=double.tryParse(price.text.trim());
    if(c==null||p==null||c<0||p<0){msg('أدخل أسعارًا رقمية غير سالبة');return;}
    setState(()=>busy=true);
    try{
      final values=<String,Object?>{
        'code':code.text.trim().isEmpty?null:code.text.trim(),'name':name.text.trim(),'english_name':englishName.text.trim(),
        'category_id':categoryId,'subcategory_id':subcategoryId,'unit':unit.text.trim().isEmpty?'قطعة':unit.text.trim(),'sale_method':weighted?'وزن':saleMethod,
        'item_type':itemType,'pricing_mode':pricingMode,'default_cash_box_id':defaultCashBoxId,
        'expiry_tracking':expiryTracking?1:0,'batch_tracking':batchTracking?1:0,'expiry_warning_days':int.tryParse(expiryWarningDays.text.trim())??30,
        'is_returnable':returnable?1:0,'visible_to_employee':visibleToEmployee?1:0,'requires_manager_approval':requiresManagerApproval?1:0,
        'cost_price':c,'sale_price':p,'notes':notes.text.trim(),'stock_tracking':tracking?1:0,
        'negative_stock':negativeStock?1:0,'is_active':active?1:0,
      };
      if(selectedId==null){selectedId=await db.insert('products',values);msg('تم إنشاء الصنف');}
      else{await db.update('products',values,where:'id=?',whereArgs:[selectedId]);msg('تم تحديث بيانات الصنف');}
      await reload();await loadChildren();
    }catch(e){msg('تعذر حفظ الصنف: $e');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> deleteProduct() async {
    if(selectedId==null)return;
    final yes=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
      title:const Text('حذف الصنف'),content:const Text('قد تمنع الحركات والأرصدة المرتبطة حذف الصنف.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('حذف'))]));
    if(yes!=true)return;
    try{await db.delete('products',where:'id=?',whereArgs:[selectedId]);clearForm();await reload();msg('تم حذف الصنف');}
    catch(e){msg('لا يمكن حذف صنف مرتبط بحركات أو أرصدة: $e');}
  }

  Future<void> editChild(String tableName,String title,List<String> fields,{Map<String,Object?>? row}) async {
    if(selectedId==null){msg('احفظ الصنف أولاً');return;}
    final controllers={for(final f in fields)f:TextEditingController(text:(row?[f]??'').toString())};
    final result=await showDialog<Map<String,Object?>?>(context:context,builder:(c)=>AlertDialog(
      title:Text(title),
      content:SizedBox(width:400,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:fields.map((f){
        if (f == 'warehouse_id' || f == 'unit_id') {
          final options = f == 'warehouse_id' ? warehouses : units;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DropdownButtonFormField<int>(
              value: int.tryParse(controllers[f]!.text),
              isExpanded: true,
              decoration: InputDecoration(labelText: f == 'warehouse_id' ? 'المخزن' : 'وحدة الصنف'),
              items: options.map((option) => DropdownMenuItem<int>(
                value: (option['id'] as num).toInt(),
                child: Text((option[f == 'warehouse_id' ? 'name' : 'unit_name'] ?? '').toString()),
              )).toList(),
              onChanged: (value) => controllers[f]!.text = value?.toString() ?? '',
            ),
          );
        }
        final label = switch (f) {
          'unit_name' => 'اسم الوحدة', 'factor' => 'معامل التحويل',
          'sale_price' => 'سعر البيع', 'barcode' => 'الباركود',
          'minimum' => 'حد النقص', 'maximum' => 'الحد الأعلى',
          'batch_no' => 'رقم الدفعة', 'expiry_date' => 'تاريخ الصلاحية YYYY-MM-DD',
          'qty' => 'الكمية', _ => f,
        };
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextField(
            controller: controllers[f],
            decoration: InputDecoration(labelText: label),
            keyboardType: ['factor', 'sale_price', 'minimum', 'maximum', 'qty'].contains(f)
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
          ),
        );
      }).toList()))),
      actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('إلغاء')),FilledButton(onPressed:(){
        final values=<String,Object?>{};
        for(final f in fields){
          final raw=controllers[f]!.text.trim();if(raw.isEmpty)continue;
          if(['factor','sale_price','minimum','maximum','qty'].contains(f)){final n=double.tryParse(raw);if(n==null){msg('تحقق من الحقول الرقمية');return;}values[f]=n;}
          else if(['unit_id','warehouse_id'].contains(f)){final n=int.tryParse(raw);if(n==null){msg('المعرف يجب أن يكون رقمًا صحيحًا');return;}values[f]=n;}
          else{values[f]=raw;}
        }
        Navigator.pop(c,values);
      },child:const Text('حفظ'))]));
    for(final c in controllers.values){c.dispose();}
    if(result==null||selectedId==null)return;
    try{
      final values=<String,Object?>{...result,'product_id':selectedId};
      if(tableName=='product_batches')values.putIfAbsent('qty',()=>0);
      if(row==null){await db.insert(tableName,values);}
      else{await db.update(tableName,values,where:'id=? AND product_id=?',whereArgs:[row['id'],selectedId]);}
      await loadChildren();msg('تم حفظ $title');
    }catch(e){msg('تعذر حفظ $title: $e');}
  }
  Future<void> deleteChild(String tableName,Map<String,Object?> row) async {
    try{await db.delete(tableName,where:'id=? AND product_id=?',whereArgs:[row['id'],selectedId]);await loadChildren();}
    catch(e){msg('تعذر الحذف: $e');}
  }
  Widget childTable(String title,String tableName,List<Map<String,Object?>> rows,List<String> keys,List<String> labels,List<String> inputFields,{bool readOnly=false}){
    return SectionCard(
      title:title+' ('+rows.length.toString()+')',
      trailing:readOnly?null:ActionButton('إضافة',icon:Icons.add,onPressed:()=>editChild(tableName,title,inputFields)),
      child:rows.isEmpty?const Padding(padding:EdgeInsets.all(16),child:Text('لا توجد بيانات')):
      SingleChildScrollView(scrollDirection:Axis.horizontal,child:DataTable(
        columns:[...labels.map((x)=>DataColumn(label:Text(x))),if(!readOnly)const DataColumn(label:Text('إجراءات'))],
        rows:rows.map((r)=>DataRow(cells:[
          ...keys.map((k)=>DataCell(Text((r[k]??'—').toString()))),
          if(!readOnly)DataCell(Row(mainAxisSize:MainAxisSize.min,children:[
            IconButton(tooltip:'تعديل',onPressed:()=>editChild(tableName,title,inputFields,row:r),icon:const Icon(Icons.edit_outlined)),
            IconButton(tooltip:'حذف',onPressed:()=>deleteChild(tableName,r),icon:const Icon(Icons.delete_outline,color:Colors.red)),
          ])),
        ])).toList(),
      )),
    );
  }

  @override   Future<void> exportProducts() async {
    final visible = products.where((row) => filter.isEmpty || row.values.any((v) => v.toString().toLowerCase().contains(filter.toLowerCase()))).toList();
    if (visible.isEmpty) { msg('لا توجد أصناف لتصديرها'); return; }
    try {
      final docs = await getApplicationDocumentsDirectory();
      final folder = Directory(p.join(docs.path, 'StoreERP', 'exports'));
      await folder.create(recursive: true);
      final file = File(p.join(folder.path, 'products_' + DateTime.now().millisecondsSinceEpoch.toString() + '.csv'));
      final header = ['المعرف', 'الكود', 'اسم الصنف', 'الاسم الإنجليزي', 'التصنيف', 'التصنيف الفرعي', 'الوحدة', 'نوع الصنف', 'نمط التسعير', 'طريقة البيع', 'الصندوق الافتراضي', 'سعر التكلفة', 'سعر البيع', 'تتبع المخزون', 'تتبع الصلاحية', 'تتبع الدفعات', 'تنبيه الانتهاء بالأيام', 'السماح بالسالب', 'قابل للإرجاع', 'ظاهر للموظف', 'يتطلب موافقة مدير', 'نشط', 'ملاحظات'];
      final data = visible.map((row) {
        final category = categories.where((x) => x['id'] == row['category_id']);
        final sub = categories.where((x) => x['id'] == row['subcategory_id']);
        final box = cashBoxes.where((x) => x['id'] == row['default_cash_box_id']);
        return [row['id'], row['code'], row['name'], row['english_name'], category.isEmpty ? '' : category.first['name'], sub.isEmpty ? '' : sub.first['name'], row['unit'], row['item_type'], row['pricing_mode'], row['sale_method'], box.isEmpty ? '' : box.first['name'], row['cost_price'], row['sale_price'], row['stock_tracking'], row['expiry_tracking'], row['batch_tracking'], row['expiry_warning_days'], row['negative_stock'], row['is_returnable'], row['visible_to_employee'], row['requires_manager_approval'], row['is_active'], row['notes']];
      }).toList();
      await file.writeAsString(String.fromCharCode(65279) + const ListToCsvConverter().convert([header, ...data]), flush: true);
      msg('تم تصدير الأصناف بصيغة CSV المتوافقة مع Excel: ' + file.path);
    } catch (e) { msg('تعذر تصدير الأصناف: ' + e.toString()); }
  }

Widget build(BuildContext context){
    final visible=products.where((p)=>filter.isEmpty||p.values.any((v)=>v.toString().toLowerCase().contains(filter.toLowerCase()))).toList();
    return Padding(padding:const EdgeInsets.all(14),child:Column(children:[
      Wrap(spacing:8,runSpacing:8,children:[
        ActionButton('جديد',icon:Icons.add,onPressed:clearForm),
        ActionButton('حفظ',icon:Icons.save,primary:true,onPressed:busy?()=>{}:saveProduct),
        ActionButton('تحديث',icon:Icons.refresh,onPressed:reload),
        ActionButton('تصدير CSV',icon:Icons.file_download_outlined,onPressed:exportProducts),
        ActionButton('تفريغ',icon:Icons.cleaning_services,onPressed:clearForm),
        ActionButton('حذف',icon:Icons.delete_outline,onPressed:deleteProduct),
        ActionButton('إغلاق',icon:Icons.close,onPressed:()=>Navigator.maybePop(context)),
      ]),
      const SizedBox(height:10),
      Expanded(child:Row(children:[
        SizedBox(width:280,child:Card(child:Padding(padding:const EdgeInsets.all(10),child:Column(children:[
          TextField(controller:search,decoration:const InputDecoration(labelText:'بحث عام عن الأصناف',prefixIcon:Icon(Icons.search)),onChanged:(v)=>setState(()=>filter=v.trim())),
          Row(children:[Expanded(child:OutlinedButton.icon(onPressed:()=>setState(()=>filter=search.text.trim()),icon:const Icon(Icons.search),label:const Text('بحث'))),IconButton(tooltip:'تحديث',onPressed:reload,icon:const Icon(Icons.refresh))]),
          const Divider(),
          Expanded(child:visible.isEmpty?const Center(child:Text('لا توجد أصناف')):ListView.builder(itemCount:visible.length,itemBuilder:(c,i){
            final p=visible[i];return ListTile(selected:(p['id'] as num).toInt()==selectedId,title:Text((p['name']??'').toString()),subtitle:Text('الكود: '+(p['code']??'—').toString()+' • السعر: '+(p['sale_price']??0).toString()),onTap:()=>selectProduct(p));
          })),
        ])))),
        const SizedBox(width:10),
        Expanded(child:Card(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Padding(padding:const EdgeInsets.all(12),child:Text(selectedId==null?'بيانات صنف جديد':'بيانات الصنف #'+selectedId.toString(),style:Theme.of(context).textTheme.titleLarge)),
          TabBar(controller:tabs,isScrollable:true,tabs:const[Tab(text:'الأساسية'),Tab(text:'الوحدات والأسعار'),Tab(text:'الباركود'),Tab(text:'إعادة الطلب'),Tab(text:'الدفعات والأرصدة')]),
          Expanded(child:TabBarView(controller:tabs,children:[
            ListView(padding:const EdgeInsets.all(14),children:[
              Wrap(spacing:10,runSpacing:10,children:[
                SizedBox(width:190,child:TextField(controller:code,decoration:const InputDecoration(labelText:'التكويد'))),
                SizedBox(width:240,child:TextField(controller:name,decoration:const InputDecoration(labelText:'اسم الصنف *'))),
                SizedBox(width:210,child:TextField(controller:englishName,decoration:const InputDecoration(labelText:'الاسم الإنجليزي'))),
                SizedBox(width:220,child:DropdownButtonFormField<int>(value:categoryId,decoration:const InputDecoration(labelText:'التصنيف'),items:categories.map((c)=>DropdownMenuItem<int>(value:(c['id'] as num).toInt(),child:Text((c['name']??'').toString()))).toList(),onChanged:(v){setState(() { categoryId = v; if (subcategoryId == v) subcategoryId = null; });})),
                SizedBox(width:170,child:TextField(controller:unit,decoration:const InputDecoration(labelText:'الوحدة الأساسية'))),
                SizedBox(width:170,child:DropdownButtonFormField<String>(value:saleMethod,decoration:const InputDecoration(labelText:'طريقة البيع'),items:const['قطعة','وزن','طول','حجم'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v)=>setState(()=>saleMethod=v??'قطعة'))),
                SizedBox(width:170,child:TextField(controller:cost,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'سعر التكلفة'))),
                SizedBox(width:170,child:TextField(controller:price,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'سعر البيع'))),
                SizedBox(width:190,child:DropdownButtonFormField<int>(value:categories.any((x)=>(x['id'] as num).toInt()==subcategoryId)?subcategoryId:null,decoration:const InputDecoration(labelText:'القسم الفرعي'),items:categories.where((x)=>(x['id'] as num).toInt()!=categoryId).map((x)=>DropdownMenuItem<int>(value:(x['id'] as num).toInt(),child:Text((x['name']??'').toString()))).toList(),onChanged:(v)=>setState(()=>subcategoryId=v))),
                SizedBox(width:170,child:DropdownButtonFormField<String>(value:itemType,decoration:const InputDecoration(labelText:'نوع الصنف'),items:const['مخزني','خدمة','مصنّع'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v)=>setState(()=>itemType=v??'مخزني'))),
                SizedBox(width:170,child:DropdownButtonFormField<String>(value:pricingMode,decoration:const InputDecoration(labelText:'نمط التسعير'),items:const['ثابت','متغير'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v)=>setState(()=>pricingMode=v??'ثابت'))),
                SizedBox(width:220,child:DropdownButtonFormField<int?>(value:cashBoxes.any((x)=>(x['id'] as num).toInt()==defaultCashBoxId)?defaultCashBoxId:null,decoration:const InputDecoration(labelText:'الصندوق الافتراضي'),items:[const DropdownMenuItem<int?>(value:null,child:Text('بدون صندوق افتراضي')),...cashBoxes.map((x)=>DropdownMenuItem<int?>(value:(x['id'] as num).toInt(),child:Text((x['name']??'').toString())))],onChanged:(v)=>setState(()=>defaultCashBoxId=v))),
                SizedBox(width:190,child:TextField(controller:expiryWarningDays,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'التنبيه قبل الانتهاء (أيام)'))),
                SizedBox(width:380,child:TextField(controller:notes,maxLines:2,decoration:const InputDecoration(labelText:'ملاحظات'))),
              ]),
              const SizedBox(height:12),
              Wrap(spacing:8,runSpacing:8,children:[
                FilterChip(label:const Text('تتبع المخزون'),selected:tracking,onSelected:(v)=>setState(()=>tracking=v)),
                FilterChip(label:const Text('تتبع الصلاحية'),selected:expiryTracking,onSelected:(v)=>setState(()=>expiryTracking=v)),
                FilterChip(label:const Text('تتبع الدفعات'),selected:batchTracking,onSelected:(v)=>setState(()=>batchTracking=v)),
                FilterChip(label:const Text('قابل للإرجاع'),selected:returnable,onSelected:(v)=>setState(()=>returnable=v)),
                FilterChip(label:const Text('ظاهر للموظف'),selected:visibleToEmployee,onSelected:(v)=>setState(()=>visibleToEmployee=v)),
                FilterChip(label:const Text('يتطلب موافقة مدير'),selected:requiresManagerApproval,onSelected:(v)=>setState(()=>requiresManagerApproval=v)),
                FilterChip(label:const Text('صنف موزون'),selected:weighted,onSelected:(v)=>setState(()=>weighted=v)),
                FilterChip(label:const Text('السماح بالمخزون السالب'),selected:negativeStock,onSelected:(v)=>setState(()=>negativeStock=v)),
                FilterChip(label:const Text('نشط'),selected:active,onSelected:(v)=>setState(()=>active=v)),
              ]),
            ]),
            ListView(padding:const EdgeInsets.all(8),children:[
              childTable('الوحدات ومعاملات التحويل','product_units',units,const['unit_name','factor','sale_price'],const['الوحدة','المعامل','سعر البيع'],const['unit_name','factor','sale_price']),
              childTable('الأرصدة حسب المخزن','inventory',stock,const['warehouse_id','qty'],const['معرف المخزن','الرصيد'],const[],readOnly:true),
            ]),
            ListView(padding:const EdgeInsets.all(8),children:[
              childTable('باركودات الصنف','barcodes',barcodes,const['barcode','unit_id'],const['الباركود','معرف الوحدة'],const['barcode','unit_id']),
            ]),
            ListView(padding:const EdgeInsets.all(8),children:[
              childTable('حدود إعادة الطلب حسب المخزن','reorder_levels',reorderLevels,const['warehouse_id','minimum','maximum'],const['معرف المخزن','حد النقص','الحد الأعلى'],const['warehouse_id','minimum','maximum']),
            ]),
            ListView(padding:const EdgeInsets.all(8),children:[
              childTable('الدفعات وتواريخ الصلاحية','product_batches',batches,const['warehouse_id','batch_no','expiry_date','qty'],const['معرف المخزن','رقم الدفعة','الصلاحية','الكمية'],const['warehouse_id','batch_no','expiry_date','qty']),
              childTable('الأرصدة الحالية','inventory',stock,const['warehouse_id','qty'],const['معرف المخزن','الرصيد'],const[],readOnly:true),
            ]),
          ])),
        ]))),
      ])),
    ]));
  }
}
