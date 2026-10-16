import 'dart:io'; 
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../data/database_helper.dart';
import '../providers/app_provider.dart';
import '../widgets/common_widgets.dart';
import 'screen_config.dart';

class DataScreen extends StatefulWidget {
  final String screenKey;
  const DataScreen({super.key, required this.screenKey});
  @override 
  State<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends State<DataScreen> {
  final Map<String, TextEditingController> _controllers = {};
  final _search = TextEditingController();
  String _filter = '';
  int? _selectedId;
  bool _busy = false;
  
  ScreenConfig get config => screenConfigs[widget.screenKey] ?? screenConfigs['products']!;
  bool get _readOnly => ['inventory','backup','counts','dailycount','monthlycount','yearlycount','countreports'].contains(widget.screenKey);
  static const _numericFields = {'cost_price','sale_price','credit_limit','balance','subtotal','discount','tax','net','paid','total','qty','factor','book_qty','count_qty','count_qty2','difference','difference_cost','amount','product_id','warehouse_id','cash_box_id','supplier_id','document_id','sales_id','customer_id','from_warehouse_id','to_warehouse_id','from_cashbox_id','to_cashbox_id','is_active'};

  final Map<String, List<Map<String, Object?>>> _referenceOptions = {};

  static const _referenceFields = <String, (String, String)>{
    'category_id': ('categories', 'name'),
    'product_id': ('products', 'name'),
    'warehouse_id': ('warehouses', 'name'),
    'cash_box_id': ('cash_boxes', 'name'),
    'customer_id': ('customers', 'name'),
    'supplier_id': ('suppliers', 'name'),
    'sales_id': ('sales_header', 'invoice_no'),
    'from_warehouse_id': ('warehouses', 'name'),
    'to_warehouse_id': ('warehouses', 'name'),
    'from_cashbox_id': ('cash_boxes', 'name'),
    'to_cashbox_id': ('cash_boxes', 'name'),
    'document_id': ('inventory_documents', 'document_no'),
  };

  @override
  void initState() {
    super.initState();
    _initControllers();
    _loadReferenceOptions();
  }

  Future<void> _loadReferenceOptions() async {
    try {
      final loaded = <String, List<Map<String, Object?>>>{};
      for (final entry in _referenceFields.entries) {
        loaded[entry.key] = await DatabaseHelper.instance.query(
          entry.value.$1,
          orderBy: entry.value.$2,
        );
      }
      if (!mounted) return;
      setState(() => _referenceOptions
        ..clear()
        ..addAll(loaded));
    } catch (_) {
      // Keep the form usable if a reference table is unavailable.
    }
  }

  Widget _fieldInput(String field, double width) {
    final reference = _referenceFields[field];
    final options = _referenceOptions[field] ?? const <Map<String, Object?>>[];
    if (reference != null && options.isNotEmpty) {
      final selected = int.tryParse(_controllers[field]!.text);
      final selectedValue = options.any((row) => (row['id'] as num?)?.toInt() == selected)
          ? selected
          : null;
      return SizedBox(
        width: width,
        child: DropdownButtonFormField<int>(
          value: selectedValue,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: fieldLabel(field),
            prefixIcon: Icon(_icon(field)),
          ),
          hint: const Text('اختر من القائمة'),
          items: options.map((row) {
            final id = (row['id'] as num).toInt();
            final label = (row[reference.$2] ?? 'بدون اسم').toString();
            return DropdownMenuItem<int>(
              value: id,
              child: Text('$label  (#$id)', overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: (value) {
            _controllers[field]!.text = value?.toString() ?? '';
            setState(() {});
          },
        ),
      );
    }
    return SizedBox(
      width: width,
      child: TextField(
        controller: _controllers[field],
        obscureText: field == 'password_hash',
        decoration: InputDecoration(
          labelText: field == 'password_hash' && _selectedId != null
              ? 'كلمة مرور جديدة (اتركها فارغة دون تغيير)'
              : fieldLabel(field),
          prefixIcon: Icon(_icon(field)),
          hintText: _numericFields.contains(field) ? 'أدخل رقمًا' : null,
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(DataScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.screenKey != widget.screenKey) {
      _clear();
      for (final controller in _controllers.values) { controller.dispose(); }
      _controllers.clear();
      _initControllers();
    }
  }

  void _initControllers() {
    for (final field in config.fields) { 
      _controllers[field] = TextEditingController(); 
    }
    _applyDefaults();
  }

  void _applyDefaults() {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final numberFields = <String, String>{
      'sales': 'invoice_no', 'purchases': 'invoice_no', 'returns': 'return_no',
      'transfers': 'transfer_no', 'damage': 'document_no', 'cashtransfers':'transfer_no', 'countdocs':'document_no',
    };
    final dateFields = <String>{'invoice_date', 'return_date', 'transfer_date', 'document_date', 'inventory_date'};
    for (final field in config.fields) {
      if (dateFields.contains(field) && _controllers[field]!.text.isEmpty) {
        _controllers[field]!.text = today;
      }
    }
    final numberField = numberFields[widget.screenKey];
    if (numberField != null && _controllers.containsKey(numberField) && _controllers[numberField]!.text.isEmpty) {
      final prefix = switch (widget.screenKey) {
        'sales' => 'S', 'purchases' => 'P', 'returns' => 'SR', 'transfers' => 'WT', 'cashtransfers' => 'CT', 'countdocs' => 'INV', _ => 'DM'
      };
      _controllers[numberField]!.text = '$prefix-${DateTime.now().millisecondsSinceEpoch}';
    }
    if (_controllers.containsKey('status') && _controllers['status']!.text.isEmpty) {
      _controllers['status']!.text = 'مسودة';
    }
    if (_controllers.containsKey('payment_method') && _controllers['payment_method']!.text.isEmpty) {
      _controllers['payment_method']!.text = 'نقدي';
    }
    if (_controllers.containsKey('unit') && _controllers['unit']!.text.isEmpty) {
      _controllers['unit']!.text = 'قطعة';
    }
    if (widget.screenKey == 'countdocs' && _controllers.containsKey('inventory_type') && _controllers['inventory_type']!.text.isEmpty) {
      _controllers['inventory_type']!.text = 'فعلي';
    }
    if (widget.screenKey == 'cashboxes' && _controllers.containsKey('is_active') && _controllers['is_active']!.text.isEmpty) {
      _controllers['is_active']!.text = '1';
    }
  }

  String? _validateRequired(Map<String, Object?> data) {
    final requiredByScreen = <String, List<String>>{
      'products': ['name'], 'customers': ['name'], 'suppliers': ['name'],
      'users': ['username', 'full_name'], 'sales': ['invoice_no', 'invoice_date'],
      'purchases': ['invoice_no', 'invoice_date'],
      'returns': ['return_no', 'return_date', 'sales_id', 'warehouse_id'],
      'inventory': ['product_id', 'warehouse_id', 'qty'],
      'transfers': ['transfer_no', 'transfer_date', 'from_warehouse_id', 'to_warehouse_id'],
      'damage': ['document_no', 'document_date', 'warehouse_id', 'document_type', 'cause'],
      'cashtransfers': ['transfer_no','from_cashbox_id','to_cashbox_id','amount'],
      'countdocs': ['document_no','inventory_date','warehouse_id','inventory_type'],
      'cashboxes': ['name'],
    };
    for (final field in requiredByScreen[widget.screenKey] ?? const <String>[]) {
      final value = data[field];
      if (value == null || value.toString().trim().isEmpty) return 'الحقل «${fieldLabel(field)}» مطلوب';
    }
    if (widget.screenKey == 'transfers' && data['from_warehouse_id'] != null && data['from_warehouse_id'] == data['to_warehouse_id']) {
      return 'يجب أن يكون المخزن المصدر مختلفًا عن المخزن المستلم';
    }
    if (widget.screenKey == 'cashtransfers' && data['from_cashbox_id'] != null && data['from_cashbox_id'] == data['to_cashbox_id']) {
      return 'يجب أن يكون الصندوق المصدر مختلفًا عن الصندوق المستلم';
    }
    if (widget.screenKey == 'cashtransfers' && (data['amount'] as num? ?? 0) <= 0) return 'مبلغ التحويل يجب أن يكون أكبر من صفر';
    for (final field in ['cost_price', 'sale_price', 'credit_limit', 'qty', 'discount', 'tax', 'net', 'paid', 'amount']) {
      final value = data[field];
      if (value is num && value < 0) return 'لا يمكن أن تكون قيمة «${fieldLabel(field)}» سالبة';
    }
    for (final field in ['invoice_date','return_date','transfer_date','document_date','inventory_date']) {
      final value = data[field];
      if (value != null && !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value.toString())) return 'التاريخ في «${fieldLabel(field)}» يجب أن يكون بصيغة YYYY-MM-DD';
    }
    if (data['paid'] is num && data['net'] is num && (data['paid'] as num) > (data['net'] as num)) {
      return 'المبلغ المدفوع لا يمكن أن يتجاوز صافي الفاتورة';
    }
    return null;
  }

  @override 
  void dispose() { 
    for (final controller in _controllers.values) { controller.dispose(); } 
    _search.dispose(); 
    super.dispose(); 
  }

  Future<void> _save() async {
    if (_readOnly) { _message(widget.screenKey == 'inventory' ? 'أرصدة المخزون للعرض فقط؛ عدّلها عبر ترحيل فاتورة أو تحويل أو جرد' : 'هذه الشاشة للعرض فقط؛ نفّذ التعديل من شاشة العمليات المناسبة'); return; }
    if (_selectedId != null && ['sales','purchases','returns','transfers','damage','cashtransfers','countdocs'].contains(widget.screenKey)) {
      final selected = await DatabaseHelper.instance.query(config.table, where:'id=?', whereArgs:[_selectedId], limit:1);
      if (selected.isNotEmpty && selected.first['status'] == 'مرحل') { _message('لا يمكن تعديل مستند مرحل؛ أنشئ مستندًا عكسيًا بدلًا من ذلك'); return; }
    }
    final data = <String,Object?>{};
    for (final field in config.fields) {
      final raw = _controllers[field]!.text.trim();
      if (raw.isEmpty) continue;
      if (_numericFields.contains(field)) {
        final value = num.tryParse(raw);
        if (value == null) { _message('القيمة في «${fieldLabel(field)}» يجب أن تكون رقمية'); return; }
        data[field] = value;
      } else { data[field] = raw; }
    }
    if (data.isEmpty) { _message('أدخل بيانات قبل الحفظ'); return; }
    final requiredError = _validateRequired(data);
    if (requiredError != null) { _message(requiredError); return; }
    
    if (config.table == 'users' && _selectedId == null && (data['password_hash'] == null || data['password_hash'].toString().isEmpty)) {
      _message('كلمة المرور مطلوبة للمستخدم الجديد'); return;
    }
    if (config.table == 'users' && data['password_hash'] != null && data['password_hash'].toString().isNotEmpty) {
      data['password_hash'] = sha256.convert(utf8.encode(data['password_hash'].toString())).toString();
    }
    if (['sales','purchases','returns','transfers','damage'].contains(widget.screenKey)) {
      data.putIfAbsent('status', () => 'مسودة');
    }
    if (widget.screenKey == 'products') data.putIfAbsent('is_active', () => 1);
    if (widget.screenKey == 'cashtransfers') data.remove('status');
    
    setState(() => _busy = true);
    try {
      final provider = context.read<AppProvider>();
      if (_selectedId == null) {
        if (config.table == 'users') { data.putIfAbsent('is_active', () => 1); data.putIfAbsent('roles', () => 'كاشير'); }
        _selectedId = await provider.create(config.table, data);
      } else {
        if (config.table == 'users' && (data['password_hash']?.toString().isEmpty ?? true)) data.remove('password_hash');
        await provider.edit(config.table, _selectedId!, data);
      }
      await _recalculateDraftTotals();
      
      if (!mounted) return; 
      await provider.refresh();
      _message('تم الحفظ بنجاح — رقم السجل $_selectedId');
      setState(() {});
    } catch (e) { 
      _message('تعذر الحفظ: $e'); 
    } finally { 
      if (mounted) setState(() => _busy = false); 
    }
  }

  Future<void> _recalculateDraftTotals() async {
    if (_selectedId == null || !['sales','purchases','returns'].contains(widget.screenKey)) return;
    final table = widget.screenKey == 'sales' ? 'sales_header' : widget.screenKey == 'purchases' ? 'purchases_header' : 'sales_returns';
    final headers = await DatabaseHelper.instance.query(table, where:'id=?', whereArgs:[_selectedId], limit:1);
    if (headers.isEmpty || headers.first['status'] == 'مرحل') return;
    if (widget.screenKey == 'returns') {
      final lines = await DatabaseHelper.instance.query('sales_return_lines', where:'return_id=?', whereArgs:[_selectedId]);
      final total = lines.fold<double>(0, (sum, line) => sum + (((line['qty'] as num?)?.toDouble() ?? 0) * ((line['price'] as num?)?.toDouble() ?? 0)));
      await DatabaseHelper.instance.update(table, {'total':total}, where:'id=?', whereArgs:[_selectedId]);
      return;
    }
    final lineTable = widget.screenKey == 'sales' ? 'sales_lines' : 'purchases_lines';
    final parentField = widget.screenKey == 'sales' ? 'sales_id' : 'purchase_id';
    final lines = await DatabaseHelper.instance.query(lineTable, where:'$parentField=?', whereArgs:[_selectedId]);
    final subtotal = lines.fold<double>(0, (sum, line) => sum + ((line['line_total'] as num?)?.toDouble() ?? 0));
    final header = headers.first;
    final discount = (header['discount'] as num?)?.toDouble() ?? 0;
    final tax = (header['tax'] as num?)?.toDouble() ?? 0;
    final net = (subtotal - discount + tax).clamp(0, double.infinity).toDouble();
    await DatabaseHelper.instance.update(table, {'subtotal':subtotal,'net':net}, where:'id=?', whereArgs:[_selectedId]);
  }

  Future<void> _addLine() async {
    if (_selectedId != null) { 
      final selected = await DatabaseHelper.instance.query(config.table, where:'id=?', whereArgs:[_selectedId], limit:1); 
      if (selected.isNotEmpty && selected.first['status'] == 'مرحل') { _message('لا يمكن إضافة بنود إلى مستند مرحل'); return; } 
    }
    if (_selectedId == null) { _message('احفظ رأس المستند وحدده أولاً'); return; }
    final isSale = widget.screenKey == 'sales';
    final isPurchase = widget.screenKey == 'purchases';
    final isTransfer = widget.screenKey == 'transfers';
    final isDamage = widget.screenKey == 'damage';
    final isReturn = widget.screenKey == 'returns';
    final isCountDoc = widget.screenKey == 'countdocs';
    if (!(isSale || isPurchase || isTransfer || isDamage || isReturn || isCountDoc)) return;
    
    final products = await DatabaseHelper.instance.query('products', where:'is_active=1', orderBy:'name');
    if (!mounted) return;
    if (products.isEmpty) { _message('أضف الأصناف أولاً'); return; }
    
    int? productId = (products.first['id'] as num).toInt();
    final qtyController = TextEditingController(text:'1');
    final priceController = TextEditingController(text: ((products.first[isPurchase ? 'cost_price' : 'sale_price'] as num?)?.toDouble() ?? 0).toString());
    final batchController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    
    final result = await showDialog<bool>(context:context, builder:(ctx) => StatefulBuilder(builder:(ctx,setDialogState) => AlertDialog(
      title:Text(isSale ? 'إضافة صنف إلى فاتورة البيع' : isPurchase ? 'إضافة صنف إلى فاتورة الشراء' : isTransfer ? 'إضافة صنف إلى التحويل' : isReturn ? 'إضافة صنف إلى المرتجع' : isCountDoc ? 'إضافة صنف إلى الجرد' : 'إضافة صنف تالف'),
      content:SizedBox(width:460, child:Form(key:formKey, child:Column(mainAxisSize:MainAxisSize.min, children:[
        DropdownButtonFormField<int>(value:productId, isExpanded:true, decoration:const InputDecoration(labelText:'الصنف'), items:products.map((p) => DropdownMenuItem<int>(value:(p['id'] as num).toInt(), child:Text('${p['name']} — ${p['code'] ?? p['id']}'))).toList(), onChanged:(v){setDialogState((){productId=v; final prod=products.firstWhere((x)=>(x['id'] as num).toInt()==v); priceController.text=((prod[isPurchase ? 'cost_price' : 'sale_price'] as num?)?.toDouble() ?? 0).toString();});}),
        const SizedBox(height:10), TextFormField(controller:qtyController, keyboardType:const TextInputType.numberWithOptions(decimal:true), decoration:InputDecoration(labelText:isCountDoc?'الكمية الفعلية':'الكمية'), validator:(v)=> (double.tryParse(v ?? '') == null || (isCountDoc ? double.parse(v!) < 0 : double.parse(v!) <= 0)) ? (isCountDoc ? 'أدخل كمية صفرية أو موجبة' : 'أدخل كمية أكبر من صفر') : null),
        if (!isTransfer && !isDamage && !isCountDoc) ...[const SizedBox(height:10),TextFormField(controller:priceController, keyboardType:const TextInputType.numberWithOptions(decimal:true), decoration:InputDecoration(labelText:isPurchase ? 'تكلفة الوحدة' : 'سعر البيع'), validator:(v)=> (double.tryParse(v ?? '') == null || double.parse(v!) < 0) ? 'أدخل مبلغًا صحيحًا' : null)],
        if (isPurchase) ...[const SizedBox(height:10),TextFormField(controller:batchController,decoration:const InputDecoration(labelText:'رقم التشغيلة (اختياري)'))],
      ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('إلغاء')),FilledButton(onPressed:(){if(formKey.currentState!.validate()) Navigator.pop(ctx,true);},child:const Text('إضافة'))]
    )));
    
    if (result != true || productId == null || !mounted) { qtyController.dispose(); priceController.dispose(); batchController.dispose(); return; }
    
    try {
      final qty = double.parse(qtyController.text);
      final price = double.tryParse(priceController.text) ?? 0;
      final table = isSale ? 'sales_lines' : isPurchase ? 'purchases_lines' : isTransfer ? 'warehouse_transfer_lines' : isReturn ? 'sales_return_lines' : isCountDoc ? 'inventory_items' : 'damage_lines';
      final parentField = isSale ? 'sales_id' : isPurchase ? 'purchase_id' : isTransfer ? 'transfer_id' : isReturn ? 'return_id' : 'document_id';
      final values = <String,Object?>{parentField:_selectedId,'product_id':productId,'qty':qty};
      
      if (isCountDoc) {
        final docs = await DatabaseHelper.instance.query('inventory_documents', where:'id=?', whereArgs:[_selectedId], limit:1);
        if (docs.isEmpty) throw StateError('مستند الجرد غير موجود');
        final warehouseId=(docs.first['warehouse_id'] as num?)?.toInt();
        if (warehouseId == null) throw StateError('حدد المخزن في رأس مستند الجرد أولاً');
        final stock=await DatabaseHelper.instance.query('inventory',where:'product_id=? AND warehouse_id=?',whereArgs:[productId,warehouseId],limit:1);
        final bookQty=stock.isEmpty?0.0:((stock.first['qty'] as num?)?.toDouble()??0);
        final already=await DatabaseHelper.instance.query('inventory_items',where:'document_id=? AND product_id=?',whereArgs:[_selectedId,productId],limit:1);
        if(already.isNotEmpty) throw StateError('الصنف موجود مسبقًا في مستند الجرد');
        values.remove('qty'); values.addAll({'book_qty':bookQty,'count_qty':qty,'count_qty2':qty,'difference':qty-bookQty,'difference_cost':0});
      }
      if (isSale) { values.addAll({'unit':'قطعة','factor':1,'price':price,'discount':0,'tax':0,'line_total':qty*price}); }
      if (isPurchase) { values.addAll({'unit':'قطعة','factor':1,'cost':price,'discount':0,'tax':0,'batch_no':batchController.text.trim(),'line_total':qty*price}); }
      if (isReturn) values.addAll({'price':price,'condition':'سليم'});
      if (isTransfer) values.addAll({'factor':1,'unit':'قطعة'});
      if (isDamage) { final prod=products.firstWhere((x)=>(x['id'] as num).toInt()==productId); values['estimated_cost']=((prod['cost_price'] as num?)?.toDouble() ?? 0); }
      if (isCountDoc) { final prod=products.firstWhere((x)=>(x['id'] as num).toInt()==productId); values['difference_cost']=(qty-((values['book_qty'] as num?)?.toDouble()??0))*((prod['cost_price'] as num?)?.toDouble()??0); }
      
      await DatabaseHelper.instance.insert(table, values);
      
      if (isSale || isPurchase || isReturn) {
        final headerTable = isSale ? 'sales_header' : isPurchase ? 'purchases_header' : 'sales_returns';
        final parentKey = isSale ? 'sales_id' : isPurchase ? 'purchase_id' : 'return_id';
        final existing = await DatabaseHelper.instance.query(table, where:'$parentKey=?', whereArgs:[_selectedId]);
        final subtotal = existing.fold<double>(0,(sum,row)=>sum+((row['line_total'] as num?)?.toDouble() ?? (((row['qty'] as num?)?.toDouble() ?? 0)*((row['price'] as num?)?.toDouble() ?? 0))));
        final headerRows=await DatabaseHelper.instance.query(headerTable,where:'id=?',whereArgs:[_selectedId],limit:1);
        final discount=headerRows.isEmpty?0.0:((headerRows.first['discount'] as num?)?.toDouble() ?? 0);
        final tax=headerRows.isEmpty?0.0:((headerRows.first['tax'] as num?)?.toDouble() ?? 0);
        final net=(subtotal-discount+tax).clamp(0,double.infinity).toDouble();
        if (isReturn) { await DatabaseHelper.instance.update(headerTable, {'total':net}, where:'id=?', whereArgs:[_selectedId]); } else { await DatabaseHelper.instance.update(headerTable, {'subtotal':subtotal,'net':net}, where:'id=?', whereArgs:[_selectedId]); }
      }
      
      if (!mounted) return; 
      await context.read<AppProvider>().refresh();
      _message('تمت إضافة البند');
    } catch(e) {
      _message('تعذر إضافة البند: $e');
    } finally {
      qtyController.dispose(); 
      priceController.dispose(); 
      batchController.dispose(); 
      if(mounted) setState((){});
    }
  }

  String? get _lineTable => switch(widget.screenKey) {'sales'=>'sales_lines','purchases'=>'purchases_lines','returns'=>'sales_return_lines','transfers'=>'warehouse_transfer_lines','damage'=>'damage_lines','countdocs'=>'inventory_items',_=>null};
  String? get _lineParent => switch(widget.screenKey) {'sales'=>'sales_id','purchases'=>'purchase_id','returns'=>'return_id','transfers'=>'transfer_id','damage'=>'document_id','countdocs'=>'document_id',_=>null};
  
  Future<void> _deleteLine(Map<String,Object?> row) async {
    final table=_lineTable, parent=_lineParent; 
    if(table==null||parent==null||_selectedId==null) return;
    
    final parentRows = await DatabaseHelper.instance.query(config.table,where:'id=?',whereArgs:[_selectedId],limit:1);
    if(parentRows.isNotEmpty && parentRows.first['status']=='مرحل'){ _message('لا يمكن تعديل بنود مستند مرحل'); return; }
    
    final yes = await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('حذف بند'),content:const Text('هل تريد حذف هذا البند من المستند؟'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('حذف'))]));
    if(yes!=true || !mounted) return;
    
    try {
      await DatabaseHelper.instance.delete(table,where:'id=? AND $parent=?',whereArgs:[row['id'],_selectedId]);
      if(['sales','purchases','returns'].contains(widget.screenKey)) {
        final parentKey=_lineParent!; 
        final rows=await DatabaseHelper.instance.query(table,where:'$parentKey=?',whereArgs:[_selectedId]);
        final total=rows.fold<double>(0,(sum,r)=>sum+((r['line_total'] as num?)?.toDouble() ?? (((r['qty'] as num?)?.toDouble()??0)*((r['price'] as num?)?.toDouble()??0))));
        if(widget.screenKey=='returns') {
          await DatabaseHelper.instance.update('sales_returns',{'total':total},where:'id=?',whereArgs:[_selectedId]);
        } else {
          final h=(await DatabaseHelper.instance.query(widget.screenKey=='sales'?'sales_header':'purchases_header',where:'id=?',whereArgs:[_selectedId],limit:1)).first;
          final discount=(h['discount'] as num?)?.toDouble()??0;
          final tax=(h['tax'] as num?)?.toDouble()??0;
          await DatabaseHelper.instance.update(widget.screenKey=='sales'?'sales_header':'purchases_header',{'subtotal':total,'net':(total-discount+tax).clamp(0,double.infinity)},where:'id=?',whereArgs:[_selectedId]);
        }
      }
      
      if (!mounted) return; 
      await context.read<AppProvider>().refresh();
      _message('تم حذف البند');
      setState((){});
    } catch(e) {
      _message('تعذر حذف البند: $e');
    }
  }

  Future<void> _postSelected() async {
    if (_selectedId == null) { _message('حدد مستندًا أولاً'); return; }
    final db = DatabaseHelper.instance;
    try {
      final headerRows = await db.query(config.table, where:'id=?', whereArgs:[_selectedId], limit:1);
      if (headerRows.isEmpty) { _message('المستند المحدد غير موجود'); return; }
      final header = headerRows.first;
      
      if (widget.screenKey == 'sales') {
        final lines = await db.query('sales_lines', where:'sales_id=?', whereArgs:[_selectedId]);
        await db.postSale(saleId:_selectedId!, warehouseId:(header['warehouse_id'] as num?)?.toInt() ?? 1, cashBoxId:(header['cash_box_id'] as num?)?.toInt() ?? 1, customerId:(header['customer_id'] as num?)?.toInt(), net:(header['net'] as num?)?.toDouble() ?? 0, paid:(header['paid'] as num?)?.toDouble() ?? 0, lines:lines.map((r)=>{'product_id':(r['product_id'] as num).toDouble(),'qty':(r['qty'] as num).toDouble(),'factor':((r['factor'] as num?)?.toDouble() ?? 1)}).toList());
      } else if (widget.screenKey == 'returns') {
        final lines = await db.query('sales_return_lines', where:'return_id=?', whereArgs:[_selectedId]);
        await db.postSalesReturn(returnId:_selectedId!, lines:lines.map((r)=>{'product_id':(r['product_id'] as num).toDouble(),'qty':(r['qty'] as num).toDouble(),'price':(r['price'] as num).toDouble(),'good':r['condition']=='سليم' ? 1.0 : 0.0}).toList());
      } else if (widget.screenKey == 'purchases') {
        final lines = await db.query('purchases_lines', where:'purchase_id=?', whereArgs:[_selectedId]);
        await db.postPurchase(purchaseId:_selectedId!, warehouseId:(header['warehouse_id'] as num?)?.toInt() ?? 1, cashBoxId:(header['cash_box_id'] as num?)?.toInt() ?? 1, supplierId:(header['supplier_id'] as num?)?.toInt(), net:(header['net'] as num?)?.toDouble() ?? 0, paid:(header['paid'] as num?)?.toDouble() ?? 0, lines:lines.map((r)=>{'product_id':(r['product_id'] as num).toDouble(),'qty':(r['qty'] as num).toDouble(),'factor':((r['factor'] as num?)?.toDouble() ?? 1),'cost':(r['cost'] as num).toDouble()}).toList());
      } else if (widget.screenKey == 'transfers') {
        final lines = await db.query('warehouse_transfer_lines', where:'transfer_id=?', whereArgs:[_selectedId]);
        await db.transferWarehouse(transferId:_selectedId!, lines:lines.map((r)=>{'product_id':(r['product_id'] as num).toDouble(),'qty':(r['qty'] as num).toDouble(),'factor':((r['factor'] as num?)?.toDouble() ?? 1)}).toList());
      } else if (widget.screenKey == 'cashtransfers') {
        await db.transferCash(transferId:_selectedId!);
      } else if (widget.screenKey == 'damage') {
        final lines = await db.query('damage_lines', where:'document_id=?', whereArgs:[_selectedId]);
        await db.postDamage(documentId:_selectedId!, lines:lines.map((r)=>{'product_id':(r['product_id'] as num).toDouble(),'qty':(r['qty'] as num).toDouble()}).toList());
      } else if (widget.screenKey == 'countdocs') {
        await db.postInventoryCount(documentId:_selectedId!);
      } else { 
        _message('لا توجد عملية ترحيل معرفة لهذه الشاشة'); return; 
      }
      
      if (!mounted) return; 
      await context.read<AppProvider>().refresh();
      _message('تم ترحيل المستند وتسجيل العملية');
      setState((){});
    } catch(e) {
      _message('فشل الترحيل: $e');
    }
  }

  Future<void> _delete(Map<String,Object?> row) async {
    if (_readOnly) { _message('لا يمكن حذف رصيد المخزون مباشرة؛ استخدم مستند حركة معتمدًا'); return; }
    if (row['status'] == 'مرحل') { _message('لا يمكن حذف مستند مرحل؛ استخدم إجراء عكسي موثق'); return; }
    final id = row['id']; if (id is! int) return;
    
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('تأكيد الحذف'), content: const Text('هل تريد حذف السجل المحدد؟ قد تمنع العلاقات حذف سجلات مستخدمة.'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف'))]));
    if (yes != true || !mounted) return;
    
    try { 
      await context.read<AppProvider>().remove(config.table, id); 
      if (_selectedId == id) _clear(); 
      _message('تم حذف السجل'); 
    } catch (e) { 
      _message('تعذر الحذف: $e'); 
    }
  }

  void _select(Map<String,Object?> row) { 
    setState(() => _selectedId = row['id'] as int?); 
    for (final field in config.fields) { 
      _controllers[field]!.text = field == 'password_hash' ? '' : (row[field] ?? '').toString(); 
    } 
  }
  
  void _clear() { 
    for (final controller in _controllers.values) { controller.clear(); } 
    setState(() { _selectedId = null; _applyDefaults(); }); 
  }
  
  void _message(String text) { 
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text))); 
  }

  Future<void> _export(List<Map<String,Object?>> rows) async {
    if (rows.isEmpty) { _message('لا توجد بيانات لتصديرها'); return; }
    try {
      final headers = rows.first.keys.where((key) => !(config.table == 'users' && key == 'password_hash')).toList();
      final csv = const ListToCsvConverter().convert([headers, ...rows.map((r) => headers.map((h) => r[h] ?? '').toList())]);
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory(p.join(dir.path, 'StoreERP', 'exports')); await folder.create(recursive: true);
      final file = File(p.join(folder.path, '${widget.screenKey}_${DateTime.now().millisecondsSinceEpoch}.csv'));
      await file.writeAsString('\uFEFF$csv', flush: true);
      _message('تم التصدير إلى: ${file.path}');
    } catch (e) { _message('تعذر التصدير: $e'); }
  }

  Future<void> _backup() async {
    setState(() => _busy = true);
    try {
      await (await DatabaseHelper.instance.database).rawQuery('PRAGMA wal_checkpoint(FULL)');
      final source = await DatabaseHelper.instance.databasePath;
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory(p.join(dir.path, 'StoreERP', 'backups')); await folder.create(recursive: true);
      final path = p.join(folder.path, 'store_${DateTime.now().toIso8601String().replaceAll(':','-')}.db');
      await File(source).copy(path);
      
      if (!mounted) return;
      await context.read<AppProvider>().create('backup_history', {'file_path': path, 'status': 'نجاح'});
      _message('تم إنشاء نسخة احتياطية: $path');
    } catch (e) { 
      _message('فشل إنشاء النسخة الاحتياطية: $e'); 
    } finally { 
      if (mounted) setState(() => _busy = false); 
    }
  }

  Future<void> _restoreBackup() async {
    final controller = TextEditingController();
    final path = await showDialog<String>(context:context, builder:(ctx)=>AlertDialog(
      title:const Text('استعادة نسخة احتياطية'),
      content:SizedBox(width:500, child:TextField(controller:controller, decoration:const InputDecoration(labelText:'المسار الكامل لملف .db', hintText:r'C:\Users\User\Documents\StoreERP\backups\store.db'))),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(ctx,controller.text.trim()),child:const Text('متابعة'))]
    ));
    
    if (path == null || path.isEmpty || !mounted) { controller.dispose(); return; }
    
    final confirmed = await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('تأكيد الاستعادة'),
      content:const Text('سيتم استبدال قاعدة البيانات الحالية بالنسخة المحددة. أنشئ نسخة احتياطية حالية قبل المتابعة. هل تريد الاستمرار؟'),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('استعادة واستبدال'))]
    ));
    
    if (confirmed != true || !mounted) { controller.dispose(); return; }
    setState(()=>_busy=true);
    
    try {
      final source=File(path);
      if (!await source.exists()) throw StateError('الملف غير موجود');
      if (await source.length() < 100) throw StateError('ملف النسخة صغير أو غير صالح');
      final raf=await source.open(); final header=await raf.read(16); await raf.close();
      if (ascii.decode(header,allowInvalid:true) != 'SQLite format 3\u0000') throw StateError('الملف المحدد ليس قاعدة SQLite صالحة');
      final target=await DatabaseHelper.instance.databasePath;
      await (await DatabaseHelper.instance.database).rawQuery('PRAGMA wal_checkpoint(FULL)');
      final docs=await getApplicationDocumentsDirectory();
      final safetyDir=Directory(p.join(docs.path,'StoreERP','backups'));
      await safetyDir.create(recursive:true);
      await File(target).copy(p.join(safetyDir.path,'pre_restore_${DateTime.now().millisecondsSinceEpoch}.db'));
      await DatabaseHelper.instance.close();
      for (final suffix in ['-wal','-shm']) { final sidecar=File('$target$suffix'); if(await sidecar.exists()) await sidecar.delete(); }
      await source.copy(target);
      await DatabaseHelper.instance.database;
      
      if (!mounted) return; 
      await context.read<AppProvider>().refresh();
      _message('تمت استعادة النسخة بنجاح. يوصى بتسجيل الخروج ثم الدخول مجددًا.');
    } catch(e) { 
      _message('تعذرت الاستعادة: $e'); 
    } finally {
      controller.dispose(); 
      if(mounted) setState(()=>_busy=false);
    }
  }

  @override 
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String,Object?>>>(
      future: context.read<AppProvider>().load(config.table),
      builder: (context, snapshot) {
        final all = snapshot.data ?? <Map<String,Object?>>[];
        final rows = all.where((row) => _filter.isEmpty || row.values.any((v) => v.toString().toLowerCase().contains(_filter.toLowerCase()))).toList();
        
        return ListView(padding: const EdgeInsets.all(18), children: [
          SectionCard(
            title: config.title, 
            trailing: Wrap(spacing: 8, children: [
              if (widget.screenKey == 'backup') ...[ActionButton('نسخة احتياطية الآن', icon: Icons.backup, primary: true, onPressed: _backup), ActionButton('استعادة نسخة', icon: Icons.settings_backup_restore, onPressed: _restoreBackup)],
              if (['sales','purchases','returns','transfers','damage','countdocs'].contains(widget.screenKey)) ActionButton('إضافة بند', icon: Icons.playlist_add, onPressed: _addLine),
              if (['sales','purchases','returns','transfers','damage','cashtransfers','countdocs'].contains(widget.screenKey)) ActionButton('ترحيل / اعتماد', icon: Icons.verified_outlined, primary: true, onPressed: _postSelected),
              if (!_readOnly) ActionButton('جديد', icon: Icons.add, onPressed: _clear),
              if (!_readOnly) ActionButton('حفظ', icon: Icons.save, primary: true, onPressed: _busy ? () {} : _save),
              if (!_readOnly) ActionButton('تفريغ', icon: Icons.cleaning_services, onPressed: _clear),
            ]), 
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, 
              children: [
                if (widget.screenKey == 'sales' || widget.screenKey == 'purchases') const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('احفظ رأس الفاتورة ثم حدده، وأضف البنود. قبل الترحيل يتم التحقق من الرصيد وتسجيل حركة المخزون والقيد المحاسبي داخل معاملة ذرية.', style: TextStyle(color: Colors.deepOrange))),
                if (_readOnly) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(widget.screenKey == 'backup' ? 'استخدم أزرار النسخ والاستعادة؛ لا تعدّل سجل النسخ يدويًا.' : widget.screenKey == 'inventory' ? 'هذه الشاشة للعرض فقط. تُحدّث الأرصدة من خلال المستندات المرحلة.' : widget.screenKey == 'counts' ? 'أدخل الكميات الفعلية من خلال مستند الجرد في شاشة متابعة مستندات الجرد، ثم رحّل المستند لتسوية الأرصدة.' : 'عرض فقط: هذه البيانات مرجعية ولا تعدّل من هذه الشاشة.', style: const TextStyle(color: Colors.blueGrey))),
                if (!_readOnly) Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: config.fields
                      .map((field) => _fieldInput(
                            field,
                            MediaQuery.sizeOf(context).width > 1050
                                ? 240
                                : MediaQuery.sizeOf(context).width * .72,
                          ))
                      .toList(),
                ),
                if (_selectedId != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text('وضع التعديل — السجل رقم $_selectedId', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold))),
              ]
            )
          ),
          
          if (_selectedId != null && _lineTable != null) ...[
            const SizedBox(height: 12),
            FutureBuilder<List<Map<String,Object?>>>(
              future: DatabaseHelper.instance.query(_lineTable!,where:'$_lineParent=?',whereArgs:[_selectedId],orderBy:'id'),
              builder: (context, lineSnapshot) {
                final lineRows=lineSnapshot.data??<Map<String,Object?>>[];
                final keys=lineRows.isEmpty?const <String>['id','product_id','qty']:lineRows.first.keys.where((k)=>!['sales_id','purchase_id','return_id','transfer_id','document_id'].contains(k)).toList();
                return SectionCard(
                  title: 'بنود المستند رقم $_selectedId (${lineRows.length})',
                  trailing: TextButton.icon(
                    onPressed: _addLine,
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة بند'),
                  ),
                  child: lineSnapshot.hasError
                      ? Text('تعذر تحميل البنود: ${lineSnapshot.error}')
                      : lineRows.isEmpty
                          ? const Text('لا توجد بنود لهذا المستند بعد')
                          : SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                columns: [
                                  ...keys.map((k) => DataColumn(label: Text(fieldLabel(k)))),
                                  const DataColumn(label: Text('إجراء')),
                                ],
                                rows: lineRows.map((r) {
                                  return DataRow(
                                    cells: [
                                      ...keys.map((k) => DataCell(Text((r[k] ?? '—').toString()))),
                                      DataCell(
                                        IconButton(
                                          tooltip: 'حذف البند',
                                          onPressed: () => _deleteLine(r),
                                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                );
              }
            ),
          ],
          
          const SizedBox(height: 16),
          
          // تم ترتيب هذا الجزء بالكامل لحل مشكلة الأقواس المتداخلة (])))),)
          SectionCard(
            title: 'السجلات والبحث (${rows.length})', 
            trailing: Wrap(
              spacing: 8, 
              children: [
                ActionButton('تصدير CSV', icon: Icons.file_download_outlined, onPressed: () => _export(rows)), 
                ActionButton('تحديث', icon: Icons.refresh, onPressed: () => setState(() {}))
              ]
            ), 
            child: Column(
              children: [
                TextField(
                  controller: _search, 
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'ابحث في جميع حقول السجلات...'), 
                  onChanged: (v) => setState(() => _filter = v.trim())
                ),
                const SizedBox(height: 12),
                
                if (_busy || snapshot.connectionState == ConnectionState.waiting) 
                  const LinearProgressIndicator(),
                  
                if (snapshot.hasError) 
                  Padding(padding: const EdgeInsets.all(16), child: Text('تعذر تحميل البيانات: ${snapshot.error}'))
                else if (rows.isEmpty) 
                  const Padding(padding: EdgeInsets.all(24), child: Text('لا توجد سجلات مطابقة'))
                else 
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal, 
                    child: DataTable(
                      columns: [
                        ...config.columns.map((field) => DataColumn(label: Text(fieldLabel(field)))), 
                        const DataColumn(label: Text('إجراءات'))
                      ], 
                      rows: rows.map((row) => DataRow(
                        selected: row['id'] == _selectedId, 
                        onSelectChanged: (_) => _select(row), 
                        cells: [
                          ...config.columns.map((field) => DataCell(
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 220), 
                              child: Text((row[field] ?? '—').toString(), overflow: TextOverflow.ellipsis)
                            )
                          )), 
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min, 
                              children: [
                                IconButton(tooltip: _readOnly ? 'عرض' : 'تعديل', onPressed: () => _select(row), icon: Icon(_readOnly ? Icons.visibility_outlined : Icons.edit_outlined, color: Colors.blue)), 
                                if (!_readOnly) 
                                  IconButton(tooltip: 'حذف', onPressed: () => _delete(row), icon: const Icon(Icons.delete_outline, color: Colors.red))
                              ]
                            )
                          )
                        ]
                      )).toList()
                    )
                  ) // نهاية SingleChildScrollView
              ]
            ) // نهاية Column
          ), // نهاية SectionCard
        ]); // نهاية ListView
      }, // نهاية builder
    ); // نهاية FutureBuilder
  }
  
  IconData _icon(String field) { if (field.contains('name')) return Icons.badge_outlined; if (field.contains('price') || field == 'net' || field == 'balance' || field == 'amount') return Icons.payments_outlined; if (field.contains('date')) return Icons.calendar_month_outlined; if (field.contains('phone') || field == 'mobile') return Icons.phone_outlined; if (field.contains('qty')) return Icons.inventory_2_outlined; return Icons.edit_note; }
}
