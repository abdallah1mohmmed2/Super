import 'dart:async';
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
  final _backupFolderController = TextEditingController();
  final _backupNameController = TextEditingController(text: 'store_backup');
  final _restorePathController = TextEditingController();
  final _backupTimeController = TextEditingController(text: '22:00');
  Timer? _backupTimer;
  bool _verifyBackup = true;
  bool _safetyCopyBeforeRestore = true;
  bool _dailyBackupEnabled = false;
  bool _lastBackupSucceeded = false;
  String _filter = '';
  int? _selectedId;
  bool _busy = false;
  
  ScreenConfig get config => screenConfigs[widget.screenKey] ?? screenConfigs['products']!;
  bool get _readOnly => ['inventory','backup','counts','dailycount','monthlycount','yearlycount','countreports'].contains(widget.screenKey);
  static const _numericFields = {'category_id','cost_price','sale_price','credit_limit','balance','subtotal','discount','tax','net','paid','total','qty','factor','book_qty','count_qty','count_qty2','difference','difference_cost','amount','product_id','warehouse_id','cash_box_id','supplier_id','document_id','sales_id','customer_id','from_warehouse_id','to_warehouse_id','from_cashbox_id','to_cashbox_id','is_active'};

  final Map<String, List<Map<String, Object?>>> _referenceOptions = {};
  bool _referencesLoading = true;

  static const _choiceFields = <String, List<String>>{
    'payment_method': ['نقدي', 'آجل', 'جزئي', 'تحويل بنكي'],
    'inventory_type': ['فعلي', 'يومي', 'شهري', 'سنوي'],
    'document_type': ['تالف', 'منتهي'],
    'is_active': ['1', '0'],
    'roles': ['مدير نظام', 'مدير', 'محاسب', 'كاشير', 'مخزن'],
    'unit': ['قطعة', 'علبة', 'كرتون', 'كيلوجرام', 'جرام', 'لتر', 'متر'],
  };

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
    if (widget.screenKey == 'backup') {
      _loadBackupSettings();
      _backupTimer = Timer.periodic(const Duration(minutes: 1), (_) => _runDailyBackupIfDue());
    }
  }

  Future<void> _loadReferenceOptions() async {
    try {
      final loaded = <String, List<Map<String, Object?>>>{};
      for (final entry in _referenceFields.entries) {
        String? where;
        if (['customer_id', 'supplier_id', 'warehouse_id', 'cash_box_id',
             'from_warehouse_id', 'to_warehouse_id', 'from_cashbox_id', 'to_cashbox_id'].contains(entry.key)) {
          where = 'is_active=1';
        } else if (entry.key == 'product_id') {
          where = 'is_active=1';
        } else if (entry.key == 'sales_id') {
          where = "status='مرحل'";
        }
        loaded[entry.key] = await DatabaseHelper.instance.query(
          entry.value.$1,
          where: where,
          orderBy: entry.value.$2,
        );
      }
      if (!mounted) return;
      setState(() {
        _referenceOptions
          ..clear()
          ..addAll(loaded);
        _referencesLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _referencesLoading = false);
      // Empty reference lists remain disabled instead of accepting arbitrary IDs.
    }
  }

  Widget _fieldInput(String field, double width) {
    if (field == 'roles') {
      const roles = ['مدير نظام', 'مدير', 'محاسب', 'كاشير', 'مخزن'];
      final selected = _controllers[field]!.text
          .split(',')
          .map((role) => role.trim())
          .where((role) => role.isNotEmpty)
          .toSet();
      return SizedBox(
        width: width,
        child: InputDecorator(
          decoration: const InputDecoration(
            labelText: 'الأدوار والصلاحيات',
            prefixIcon: Icon(Icons.admin_panel_settings_outlined),
            border: OutlineInputBorder(),
          ),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: roles.map((role) {
              return FilterChip(
                label: Text(role),
                selected: selected.contains(role),
                onSelected: (checked) {
                  if (checked) {
                    selected.add(role);
                  } else {
                    selected.remove(role);
                  }
                  _controllers[field]!.text = roles
                      .where(selected.contains)
                      .join(', ');
                  setState(() {});
                },
              );
            }).toList(),
          ),
        ),
      );
    }
    final choices = _choiceFields[field];
    if (choices != null) {
      final current = _controllers[field]!.text;
      return SizedBox(
        width: width,
        child: DropdownButtonFormField<String>(
          value: choices.contains(current) ? current : null,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: fieldLabel(field),
            prefixIcon: Icon(_icon(field)),
          ),
          hint: const Text('اختر قيمة'),
          items: choices.map((value) => DropdownMenuItem<String>(
            value: value,
            child: Text(value == '1' ? 'نعم / نشط' : value == '0' ? 'لا / غير نشط' : value),
          )).toList(),
          onChanged: (value) {
            _controllers[field]!.text = value ?? '';
            setState(() {});
          },
        ),
      );
    }
    final reference = _referenceFields[field];
    final options = _referenceOptions[field] ?? const <Map<String, Object?>>[];
    if (reference != null) {
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
            helperText: options.isEmpty
                ? (_referencesLoading ? 'جارٍ تحميل الخيارات...' : 'لا توجد سجلات مرجعية؛ أضفها من شاشتها أولاً')
                : null,
          ),
          hint: Text(options.isEmpty ? 'لا توجد خيارات' : 'اختر من القائمة'),
          items: options.map((row) {
            final id = (row['id'] as num).toInt();
            final label = (row[reference.$2] ?? 'بدون اسم').toString();
            return DropdownMenuItem<int>(
              value: id,
              child: Text('$label  (#$id)', overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: options.isEmpty
              ? null
              : (value) {
                  _controllers[field]!.text = value?.toString() ?? '';
                  setState(() {});
                },
        ),
      );
    }
    return SizedBox(
      width: width,
      child: TextField(
        readOnly: widget.screenKey == 'suppliers' && field == 'balance',
        controller: _controllers[field],
        obscureText: field == 'password_hash' || field == 'confirm_password',
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
      _referencesLoading = true;
      _loadReferenceOptions();
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
    if (['cashboxes','suppliers','users'].contains(widget.screenKey) && _controllers.containsKey('is_active') && _controllers['is_active']!.text.isEmpty) {
      _controllers['is_active']!.text = '1';
    }
    if (widget.screenKey == 'suppliers' && _controllers.containsKey('balance') && _controllers['balance']!.text.isEmpty) { _controllers['balance']!.text = '0'; }
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
    _backupFolderController.dispose();
    _backupNameController.dispose();
    _restorePathController.dispose();
    _backupTimeController.dispose();
    _backupTimer?.cancel();
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
      if (field == 'confirm_password') continue; // UI-only confirmation; never stored.
      if (widget.screenKey == 'suppliers' && field == 'balance') continue; // Ledger-derived balance.
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
    if (config.table == 'users') {
      final password = _controllers['password_hash']!.text;
      final confirmation = _controllers['confirm_password']!.text;
      if (password.isNotEmpty && password.length < 6) { _message('يجب ألا تقل كلمة المرور عن 6 أحرف'); return; }
      if (password.isNotEmpty && password != confirmation) { _message('كلمة المرور وتأكيدها غير متطابقين'); return; }
      if (_selectedId == null && confirmation.isEmpty) { _message('يرجى تأكيد كلمة المرور'); return; }
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
      if (widget.screenKey == 'sales') await _ensureManagerApprovalRequest();
      await _recalculateDraftTotals();
      
      if (!mounted) return; 
      await provider.refresh();
      await _loadReferenceOptions();
      _message('تم الحفظ بنجاح — رقم السجل $_selectedId');
      setState(() {});
    } catch (e) { 
      _message('تعذر الحفظ: $e'); 
    } finally { 
      if (mounted) setState(() => _busy = false); 
    }
  }

  Future<void> _ensureManagerApprovalRequest() async {
    if (_selectedId == null || widget.screenKey != 'sales') return;
    final headers = await DatabaseHelper.instance.query(
      'sales_header',
      where: 'id=?',
      whereArgs: [_selectedId],
      limit: 1,
    );
    if (headers.isEmpty) return;
    final header = headers.first;
    final customerId = (header['customer_id'] as num?)?.toInt();
    if (customerId == null) return;
    final customers = await DatabaseHelper.instance.query(
      'customers',
      where: 'id=?',
      whereArgs: [customerId],
      limit: 1,
    );
    if (customers.isEmpty || ((customers.first['manager_approval'] as num?)?.toInt() ?? 0) != 1) return;
    final requests = await DatabaseHelper.instance.query(
      'approval_requests',
      where: 'entity_type=? AND entity_id=?',
      whereArgs: ['sales', _selectedId],
      orderBy: 'id DESC',
      limit: 1,
    );
    final now = DateTime.now().toIso8601String();
    final data = <String,Object?>{
      'entity_type': 'sales',
      'entity_id': _selectedId,
      'request_type': 'اعتماد فاتورة مبيعات',
      'reference': (header['invoice_no'] ?? _selectedId).toString(),
      'requested_by': context.read<AppProvider>().currentUser,
      'request_date': now,
      'request_notes': 'العميل المحدد يتطلب موافقة المدير قبل ترحيل الفاتورة.',
      'status': 'معلق',
      'decision_notes': null,
      'decided_by': null,
      'decided_at': null,
    };
    if (requests.isEmpty) {
      await DatabaseHelper.instance.insert('approval_requests', data);
    } else if (requests.first['status'] != 'معلق') {
      await DatabaseHelper.instance.update(
        'approval_requests',
        data,
        where: 'id=?',
        whereArgs: [requests.first['id']],
      );
    }
    if (mounted) {
      await context.read<AppProvider>().refresh();
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
    final expiryController = TextEditingController();
    final productionController = TextEditingController();
    final discountController = TextEditingController(text:'0');
    final taxController = TextEditingController(text:'0');
    final productSearchController = TextEditingController();
    final allUnits = await DatabaseHelper.instance.query('product_units', orderBy:'unit_name');
    List<Map<String,Object?>> unitOptions = allUnits.where((u)=>(u['product_id'] as num?)?.toInt()==productId).toList();
    int? selectedUnitId = unitOptions.isEmpty ? null : (unitOptions.first['id'] as num).toInt();
    double unitFactor = unitOptions.isEmpty ? 1 : ((unitOptions.first['factor'] as num?)?.toDouble() ?? 1);
    String returnCondition = 'سليم';
    final formKey = GlobalKey<FormState>();
    
    final result = await showDialog<bool>(context:context, builder:(ctx) => StatefulBuilder(builder:(ctx,setDialogState) => AlertDialog(
      title:Text(isSale ? 'إضافة صنف إلى فاتورة البيع' : isPurchase ? 'إضافة صنف إلى فاتورة الشراء' : isTransfer ? 'إضافة صنف إلى التحويل' : isReturn ? 'إضافة صنف إلى المرتجع' : isCountDoc ? 'إضافة صنف إلى الجرد' : 'إضافة صنف تالف'),
      content:SizedBox(width:460, child:Form(key:formKey, child:Column(mainAxisSize:MainAxisSize.min, children:[
        TextField(controller:productSearchController, decoration:const InputDecoration(labelText:'بحث بالاسم أو الكود أو امسح الباركود', prefixIcon:Icon(Icons.search), hintText:'اكتب الاسم / الكود ثم اختر الصنف'), onChanged:(_)=>setDialogState((){}), onSubmitted:(value) async { final query=value.trim(); final found=await DatabaseHelper.instance.query('barcodes',where:'barcode=?',whereArgs:[query],limit:1); int? foundId=found.isEmpty?null:(found.first['product_id'] as num).toInt(); final matches=products.where((x)=>(x['name']??'').toString().toLowerCase().contains(query.toLowerCase()) || (x['code']??'').toString().toLowerCase()==query.toLowerCase() || (x['id']??'').toString()==query).toList(); foundId ??= matches.isEmpty?null:(matches.first['id'] as num).toInt(); if(foundId!=null){final prod=products.firstWhere((x)=>(x['id'] as num).toInt()==foundId); setDialogState((){productId=foundId; productSearchController.clear(); unitOptions=allUnits.where((u)=>(u['product_id'] as num?)?.toInt()==foundId).toList(); selectedUnitId=unitOptions.isEmpty?null:(unitOptions.first['id'] as num).toInt(); unitFactor=unitOptions.isEmpty?1:((unitOptions.first['factor'] as num?)?.toDouble()??1); priceController.text=((prod[isPurchase ? 'cost_price' : 'sale_price'] as num?)?.toDouble()??0).toString();});} else {setDialogState(()=>productSearchController.clear());}}),
        const SizedBox(height:8),
        DropdownButtonFormField<int>(initialValue:productId, isExpanded:true, decoration:const InputDecoration(labelText:'الصنف'), items:products.map((p) => DropdownMenuItem<int>(value:(p['id'] as num).toInt(), child:Text('${p['name']} — ${p['code'] ?? p['id']}'))).toList(), onChanged:(v){setDialogState((){productId=v; final prod=products.firstWhere((x)=>(x['id'] as num).toInt()==v); unitOptions=allUnits.where((u)=>(u['product_id'] as num?)?.toInt()==v).toList(); selectedUnitId=unitOptions.isEmpty?null:(unitOptions.first['id'] as num).toInt(); unitFactor=unitOptions.isEmpty?1:((unitOptions.first['factor'] as num?)?.toDouble()??1); priceController.text=((prod[isPurchase ? 'cost_price' : 'sale_price'] as num?)?.toDouble() ?? 0).toString();});}),
        if (!isTransfer && !isCountDoc && unitOptions.isNotEmpty) ...[const SizedBox(height:10), DropdownButtonFormField<int>(initialValue:selectedUnitId, isExpanded:true, decoration:const InputDecoration(labelText:'الوحدة'), items:unitOptions.map((u)=>DropdownMenuItem<int>(value:(u['id'] as num).toInt(),child:Text('${u['unit_name']} (×${u['factor']})'))).toList(), onChanged:(v){setDialogState((){selectedUnitId=v; final u=unitOptions.firstWhere((x)=>(x['id'] as num).toInt()==v); unitFactor=(u['factor'] as num?)?.toDouble()??1; final prod=products.firstWhere((x)=>(x['id'] as num).toInt()==productId); final base=(prod[isPurchase?'cost_price':'sale_price'] as num?)?.toDouble()??0; final unitPrice=(u['sale_price'] as num?)?.toDouble()??0; priceController.text=((isSale && unitPrice>0)?unitPrice:base*unitFactor).toString();});})],
        const SizedBox(height:10), TextFormField(controller:qtyController, keyboardType:const TextInputType.numberWithOptions(decimal:true), decoration:InputDecoration(labelText:isCountDoc?'الكمية الفعلية':'الكمية'), validator:(v)=> (double.tryParse(v ?? '') == null || (isCountDoc ? double.parse(v!) < 0 : double.parse(v!) <= 0)) ? (isCountDoc ? 'أدخل كمية صفرية أو موجبة' : 'أدخل كمية أكبر من صفر') : null),
        if (!isTransfer && !isDamage && !isCountDoc) ...[const SizedBox(height:10),TextFormField(controller:priceController, keyboardType:const TextInputType.numberWithOptions(decimal:true), decoration:InputDecoration(labelText:isPurchase ? 'سعر الشراء للوحدة' : 'سعر الوحدة'), validator:(v)=> (double.tryParse(v ?? '') == null || double.parse(v!) < 0) ? 'أدخل مبلغًا صحيحًا' : null)],
        if (isSale || isPurchase) ...[const SizedBox(height:10),Row(children:[Expanded(child:TextFormField(controller:discountController,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'الخصم'))),const SizedBox(width:10),Expanded(child:TextFormField(controller:taxController,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'الضريبة')))])],
        if (isPurchase) ...[const SizedBox(height:10),TextFormField(controller:batchController,decoration:const InputDecoration(labelText:'رقم التشغيلة (اختياري)')),const SizedBox(height:10),TextFormField(controller:productionController,decoration:const InputDecoration(labelText:'تاريخ الإنتاج YYYY-MM-DD')),const SizedBox(height:10),TextFormField(controller:expiryController,decoration:const InputDecoration(labelText:'تاريخ الانتهاء YYYY-MM-DD'))],
        if (isDamage) ...[const SizedBox(height:10),TextFormField(controller:batchController,decoration:const InputDecoration(labelText:'رقم الدفعة (اختياري)'))],
        if (isReturn) ...[const SizedBox(height:10),DropdownButtonFormField<String>(initialValue:returnCondition,decoration:const InputDecoration(labelText:'حالة الصنف المرتجع'),items:const ['سليم','تالف','غير قابل للبيع'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v)=>setDialogState(()=>returnCondition=v??'سليم'))],
      ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('إلغاء')),FilledButton(onPressed:(){if(formKey.currentState!.validate()) Navigator.pop(ctx,true);},child:const Text('إضافة'))]
    )));
    
    if (result != true || productId == null || !mounted) { qtyController.dispose(); priceController.dispose(); batchController.dispose(); expiryController.dispose(); productionController.dispose(); discountController.dispose(); taxController.dispose(); productSearchController.dispose(); return; }
    
    try {
      final qty = double.parse(qtyController.text);
      final price = double.tryParse(priceController.text) ?? 0;
      final lineDiscount = double.tryParse(discountController.text) ?? 0;
      final lineTax = double.tryParse(taxController.text) ?? 0;
      if (lineDiscount < 0 || lineTax < 0) throw StateError('الخصم والضريبة لا يمكن أن يكونا سالبين');
      final expiry = expiryController.text.trim();
      final production = productionController.text.trim();
      if (isPurchase && expiry.isNotEmpty && !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(expiry)) throw StateError('تاريخ الانتهاء يجب أن يكون بصيغة YYYY-MM-DD');
      if (isPurchase && production.isNotEmpty && !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(production)) throw StateError('تاريخ الإنتاج يجب أن يكون بصيغة YYYY-MM-DD');
      final table = isSale ? 'sales_lines' : isPurchase ? 'purchases_lines' : isTransfer ? 'warehouse_transfer_lines' : isReturn ? 'sales_return_lines' : isCountDoc ? 'inventory_items' : 'damage_lines';
      final parentField = isSale ? 'sales_id' : isPurchase ? 'purchase_id' : isTransfer ? 'transfer_id' : isReturn ? 'return_id' : 'document_id';
      if ((isSale || isPurchase || isReturn) && unitFactor <= 0) throw StateError('معامل تحويل الوحدة يجب أن يكون أكبر من صفر');
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
      final selectedProduct = products.firstWhere((x)=>(x['id'] as num).toInt()==productId);
      final unitName = unitOptions.where((u)=>(u['id'] as num?)?.toInt()==selectedUnitId).map((u)=>(u['unit_name']??'').toString()).firstWhere((name)=>name.isNotEmpty, orElse:()=>(selectedProduct['unit']??'قطعة').toString());
      if (isSale) { values.addAll({'unit':unitName,'factor':unitFactor,'price':price,'discount':lineDiscount,'tax':lineTax,'line_total':(qty*price-lineDiscount+lineTax).clamp(0,double.infinity)}); }
      if (isPurchase) { values.addAll({'unit':unitName,'factor':unitFactor,'cost':price,'discount':lineDiscount,'tax':lineTax,'batch_no':batchController.text.trim(),'production_date':production.isEmpty?null:production,'expiry_date':expiry.isEmpty?null:expiry,'line_total':(qty*price-lineDiscount+lineTax).clamp(0,double.infinity)}); }
      if (isReturn) values.addAll({'qty':qty*unitFactor,'price':price/unitFactor,'condition':returnCondition});
      if (isTransfer) values.addAll({'factor':1,'unit':'قطعة'});
      if (isDamage) { final prod=products.firstWhere((x)=>(x['id'] as num).toInt()==productId); values['qty']=qty*unitFactor; values['batch_no']=batchController.text.trim().isEmpty?null:batchController.text.trim(); values['estimated_cost']=((prod['cost_price'] as num?)?.toDouble() ?? 0); }
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
      batchController.dispose(); expiryController.dispose(); productionController.dispose(); discountController.dispose(); taxController.dispose(); productSearchController.dispose();
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
        final customerId = (header['customer_id'] as num?)?.toInt();
        if (customerId != null) {
          final customerRows = await db.query('customers', where: 'id=?', whereArgs: [customerId], limit: 1);
          final requiresApproval = customerRows.isNotEmpty && ((customerRows.first['manager_approval'] as num?)?.toInt() ?? 0) == 1;
          if (requiresApproval) {
            final requests = await db.query('approval_requests', where: 'entity_type=? AND entity_id=?', whereArgs: ['sales', _selectedId], orderBy: 'id DESC', limit: 1);
            if (requests.isEmpty || requests.first['status'] != 'معتمد') {
              throw StateError('هذه الفاتورة تحتاج اعتماد المدير قبل الترحيل');
            }
          }
        }
        if (header['warehouse_id'] == null || header['cash_box_id'] == null) {
          throw StateError('حدد المخزن والصندوق في رأس فاتورة المبيعات قبل الترحيل');
        }
        final lines = await db.query('sales_lines', where:'sales_id=?', whereArgs:[_selectedId]);
        await db.postSale(saleId:_selectedId!, warehouseId:(header['warehouse_id'] as num?)?.toInt() ?? 1, cashBoxId:(header['cash_box_id'] as num?)?.toInt() ?? 1, customerId:(header['customer_id'] as num?)?.toInt(), net:(header['net'] as num?)?.toDouble() ?? 0, paid:(header['paid'] as num?)?.toDouble() ?? 0, lines:lines.map((r)=>{'product_id':(r['product_id'] as num).toDouble(),'qty':(r['qty'] as num).toDouble(),'factor':((r['factor'] as num?)?.toDouble() ?? 1)}).toList());
      } else if (widget.screenKey == 'returns') {
        final lines = await db.query('sales_return_lines', where:'return_id=?', whereArgs:[_selectedId]);
        await db.postSalesReturn(returnId:_selectedId!, lines:lines.map((r)=>{'product_id':(r['product_id'] as num).toDouble(),'qty':(r['qty'] as num).toDouble(),'price':(r['price'] as num).toDouble(),'good':r['condition']=='سليم' ? 1.0 : 0.0}).toList());
      } else if (widget.screenKey == 'purchases') {
        if (header['warehouse_id'] == null || header['cash_box_id'] == null || header['supplier_id'] == null) {
          throw StateError('حدد المخزن والصندوق والمورد في رأس فاتورة المشتريات قبل الترحيل');
        }
        final lines = await db.query('purchases_lines', where:'purchase_id=?', whereArgs:[_selectedId]);
        await db.postPurchase(purchaseId:_selectedId!, warehouseId:(header['warehouse_id'] as num?)?.toInt() ?? 1, cashBoxId:(header['cash_box_id'] as num?)?.toInt() ?? 1, supplierId:(header['supplier_id'] as num?)?.toInt(), net:(header['net'] as num?)?.toDouble() ?? 0, paid:(header['paid'] as num?)?.toDouble() ?? 0, lines:lines.map((r)=> <String,Object?>{'product_id':r['product_id'],'qty':r['qty'],'factor':r['factor'] ?? 1,'cost':r['cost'],'batch_no':r['batch_no'],'production_date':r['production_date'],'expiry_date':r['expiry_date']}).toList());
      } else if (widget.screenKey == 'transfers') {
        if (header['from_warehouse_id'] == null || header['to_warehouse_id'] == null) {
          throw StateError('حدد المخزن المصدر والمخزن المستلم قبل الترحيل');
        }
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

  String get _paymentDocumentType => widget.screenKey == 'sales' ? 'sales' : widget.screenKey == 'purchases' ? 'purchases' : 'returns';

  Future<void> _syncPaidAmount() async {
    if (_selectedId == null || widget.screenKey == 'returns') return;
    final payments = await DatabaseHelper.instance.query('document_payments', where: 'document_type=? AND document_id=?', whereArgs: [_paymentDocumentType, _selectedId]);
    final paid = payments.fold<double>(0, (sum, row) => sum + ((row['amount'] as num?)?.toDouble() ?? 0));
    final table = widget.screenKey == 'sales' ? 'sales_header' : 'purchases_header';
    await DatabaseHelper.instance.update(table, {'paid': paid}, where: 'id=?', whereArgs: [_selectedId]);
  }

  Future<void> _loadOriginalInvoice() async {
    if (widget.screenKey != 'returns' || _selectedId == null) { _message('احفظ رأس المرتجع وحدده أولاً'); return; }
    final returns = await DatabaseHelper.instance.query('sales_returns', where: 'id=?', whereArgs: [_selectedId], limit: 1);
    if (returns.isEmpty || returns.first['status'] == 'مرحل') { _message('المرتجع غير موجود أو مرحل بالفعل'); return; }
    final salesId = (returns.first['sales_id'] as num?)?.toInt();
    if (salesId == null) { _message('اختر الفاتورة الأصلية من حقل «معرف فاتورة البيع» أولاً'); return; }
    final saleHeaders = await DatabaseHelper.instance.query('sales_header', where: 'id=?', whereArgs: [salesId], limit: 1);
    if (saleHeaders.isEmpty || saleHeaders.first['status'] != 'مرحل') { _message('يجب اختيار فاتورة بيع مرحلة'); return; }
    final originalHeader = saleHeaders.first;
    final originalCustomerId = (originalHeader['customer_id'] as num?)?.toInt();
    final originalWarehouseId = (originalHeader['warehouse_id'] as num?)?.toInt();
    if (originalWarehouseId == null) { _message('الفاتورة الأصلية لا تحتوي على مخزن'); return; }
    await DatabaseHelper.instance.update('sales_returns', {'customer_id': originalCustomerId, 'warehouse_id': originalWarehouseId}, where: 'id=?', whereArgs: [_selectedId]);
    if (_controllers.containsKey('customer_id')) _controllers['customer_id']!.text = originalCustomerId?.toString() ?? '';
    if (_controllers.containsKey('warehouse_id')) _controllers['warehouse_id']!.text = originalWarehouseId.toString();
    await context.read<AppProvider>().refresh();
    final soldLines = await DatabaseHelper.instance.query('sales_lines', where: 'sales_id=?', whereArgs: [salesId], orderBy: 'id');
    if (soldLines.isEmpty) { _message('الفاتورة الأصلية لا تحتوي على أصناف'); return; }
    final allReturns = await DatabaseHelper.instance.query('sales_returns', where: 'sales_id=? AND status=?', whereArgs: [salesId, 'مرحل']);
    final alreadyReturned = <int,double>{};
    for (final ret in allReturns) {
      final lines = await DatabaseHelper.instance.query('sales_return_lines', where: 'return_id=?', whereArgs: [ret['id']]);
      for (final line in lines) {
        final pid = (line['product_id'] as num).toInt();
        alreadyReturned[pid] = (alreadyReturned[pid] ?? 0) + ((line['qty'] as num?)?.toDouble() ?? 0);
      }
    }
    final products = await DatabaseHelper.instance.query('products');
    int? lineId = (soldLines.first['id'] as num).toInt();
    final qtyController = TextEditingController(text: '1');
    String condition = 'سليم';
    if (!mounted) { qtyController.dispose(); return; }
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
      final selectedLine = soldLines.firstWhere((line) => (line['id'] as num).toInt() == lineId);
      final pid = (selectedLine['product_id'] as num).toInt();
      final factor = ((selectedLine['factor'] as num?)?.toDouble() ?? 1).clamp(0.000001, double.infinity).toDouble();
      final soldQtyBase = soldLines.where((line) => (line['product_id'] as num).toInt() == pid).fold<double>(0, (sum, line) => sum + (((line['qty'] as num?)?.toDouble() ?? 0) * ((line['factor'] as num?)?.toDouble() ?? 1)));
      final remainingBase = (soldQtyBase - (alreadyReturned[pid] ?? 0)).clamp(0, double.infinity).toDouble();
      final remaining = remainingBase / factor;
      return AlertDialog(
        title: Text('استدعاء الفاتورة الأصلية ${saleHeaders.first['invoice_no'] ?? salesId}'),
        content: SizedBox(width: 540, child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<int>(initialValue: lineId, isExpanded: true, decoration: const InputDecoration(labelText: 'الصنف المباع'), items: soldLines.map((line) {
            final id = (line['id'] as num).toInt();
            final productId = (line['product_id'] as num).toInt();
            final name = products.where((p) => (p['id'] as num?)?.toInt() == productId).map((p) => p['name'] ?? 'صنف').firstWhere((_) => true, orElse: () => 'صنف');
            final qty = (line['qty'] as num?)?.toDouble() ?? 0;
            return DropdownMenuItem<int>(value: id, child: Text('${name} — المباع: ${qty}'));
          }).toList(), onChanged: (v) => setDialogState(() { lineId = v; qtyController.text = '1'; })),
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerRight, child: Text('المتبقي للإرجاع بوحدة الصنف المختارة: ${remaining.toStringAsFixed(3)}')),
          TextField(controller: qtyController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'الكمية المرتجعة')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(initialValue: condition, decoration: const InputDecoration(labelText: 'حالة الصنف'), items: const ['سليم','تالف','غير قابل للبيع'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => setDialogState(() => condition = v ?? 'سليم')),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إضافة إلى المرتجع'))],
      );
    }));
    if (ok != true || !mounted || lineId == null) { qtyController.dispose(); return; }
    try {
      final line = soldLines.firstWhere((row) => (row['id'] as num).toInt() == lineId);
      final pid = (line['product_id'] as num).toInt();
      final qty = double.tryParse(qtyController.text.trim());
      final factor = ((line['factor'] as num?)?.toDouble() ?? 1).clamp(0.000001, double.infinity).toDouble();
      final soldQtyBase = soldLines.where((row) => (row['product_id'] as num).toInt() == pid).fold<double>(0, (sum, row) => sum + (((row['qty'] as num?)?.toDouble() ?? 0) * ((row['factor'] as num?)?.toDouble() ?? 1)));
      final remaining = (soldQtyBase - (alreadyReturned[pid] ?? 0)).clamp(0, double.infinity).toDouble() / factor;
      if (qty == null || qty <= 0 || qty > remaining) throw StateError('الكمية يجب أن تكون أكبر من صفر وألا تتجاوز المتبقي (${remaining.toStringAsFixed(3)})');
      final exists = await DatabaseHelper.instance.query('sales_return_lines', where: 'return_id=? AND product_id=?', whereArgs: [_selectedId, pid]);
      if (exists.isNotEmpty) throw StateError('هذا الصنف موجود بالفعل في المرتجع الحالي؛ احذف السطر أو عدّله قبل الإضافة مرة أخرى');
      final price = (line['price'] as num?)?.toDouble() ?? 0;
      // Store return quantity in base stock units so inventory and over-return checks stay consistent.
      await DatabaseHelper.instance.insert('sales_return_lines', {'return_id': _selectedId, 'product_id': pid, 'qty': qty * factor, 'price': price / factor, 'condition': condition});
      final current = await DatabaseHelper.instance.query('sales_return_lines', where: 'return_id=?', whereArgs: [_selectedId]);
      final total = current.fold<double>(0, (sum, row) => sum + (((row['qty'] as num?)?.toDouble() ?? 0) * ((row['price'] as num?)?.toDouble() ?? 0)));
      await DatabaseHelper.instance.update('sales_returns', {'total': total}, where: 'id=?', whereArgs: [_selectedId]);
      if (mounted) { await context.read<AppProvider>().refresh(); _message('تمت إضافة الصنف من الفاتورة الأصلية'); setState(() {}); }
    } catch (e) { _message('تعذر استدعاء الصنف: $e'); }
    qtyController.dispose();
  }

  Future<void> _addPayment() async {
    if (_selectedId == null || !['sales','purchases','returns'].contains(widget.screenKey)) { _message('احفظ المستند وحدده أولاً'); return; }
    final headerTable = widget.screenKey == 'sales' ? 'sales_header' : widget.screenKey == 'purchases' ? 'purchases_header' : 'sales_returns';
    final headerRows = await DatabaseHelper.instance.query(headerTable, where: 'id=?', whereArgs: [_selectedId], limit: 1);
    if (headerRows.isEmpty) { _message('المستند غير موجود'); return; }
    if (headerRows.first['status'] == 'مرحل') { _message('لا يمكن تعديل دفعات مستند مرحل'); return; }
    final amountController = TextEditingController();
    final referenceController = TextEditingController();
    final notesController = TextEditingController();
    String method = 'نقدي';
    final paymentMethods = widget.screenKey == 'returns'
        ? const ['نقدي', 'بطاقة', 'تحويل بنكي', 'شيك', 'على الرصيد']
        : const ['نقدي', 'بطاقة', 'تحويل بنكي', 'شيك'];
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) => AlertDialog(
      title: Text(widget.screenKey == 'returns' ? 'إضافة تسوية / دفعة مرتجع' : 'إضافة دفعة'),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: amountController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'المبلغ')),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(initialValue: method, decoration: const InputDecoration(labelText: 'طريقة السداد'), items: paymentMethods.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => setDialogState(() => method = v ?? 'نقدي')),
        const SizedBox(height: 10),
        TextField(controller: referenceController, decoration: const InputDecoration(labelText: 'رقم مرجعي (اختياري)')),
        const SizedBox(height: 10),
        TextField(controller: notesController, decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)')),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إضافة الدفعة'))],
    )));
    if (ok != true || !mounted) { amountController.dispose(); referenceController.dispose(); notesController.dispose(); return; }
    final amount = double.tryParse(amountController.text.trim());
    if (amount == null || amount <= 0) { _message('أدخل مبلغًا أكبر من صفر'); amountController.dispose(); referenceController.dispose(); notesController.dispose(); return; }
    try {
      final existing = await DatabaseHelper.instance.query('document_payments', where: 'document_type=? AND document_id=?', whereArgs: [_paymentDocumentType, _selectedId]);
      final currentPaid = existing.fold<double>(0, (sum, row) => sum + ((row['amount'] as num?)?.toDouble() ?? 0));
      final total = ((headerRows.first['net'] ?? headerRows.first['total']) as num?)?.toDouble() ?? 0;
      if (currentPaid + amount > total + 0.005) throw StateError('إجمالي الدفعات يتجاوز إجمالي المستند');
      await DatabaseHelper.instance.insert('document_payments', {
        'document_type': _paymentDocumentType, 'document_id': _selectedId,
        'payment_date': DateTime.now().toIso8601String().substring(0, 10),
        'method': method, 'amount': amount,
        'reference': referenceController.text.trim(), 'notes': notesController.text.trim(),
      });
      await _syncPaidAmount();
      if (mounted) { await context.read<AppProvider>().refresh(); _message(widget.screenKey == 'returns' ? 'تم تسجيل التسوية المالية للمرتجع' : 'تمت إضافة الدفعة وتحديث المدفوع'); setState(() {}); }
    } catch (e) { _message('تعذرت إضافة الدفعة: $e'); }
    amountController.dispose(); referenceController.dispose(); notesController.dispose();
  }

  Future<void> _deletePayment(Map<String,Object?> row) async {
    if (_selectedId == null) return;
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('حذف الدفعة'), content: const Text('هل تريد حذف هذه الدفعة؟'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف'))]));
    if (yes != true || !mounted) return;
    try {
      await DatabaseHelper.instance.delete('document_payments', where: 'id=? AND document_type=? AND document_id=?', whereArgs: [row['id'], _paymentDocumentType, _selectedId]);
      await _syncPaidAmount();
      if (mounted) { await context.read<AppProvider>().refresh(); _message('تم حذف الدفعة'); setState(() {}); }
    } catch (e) { _message('تعذر حذف الدفعة: $e'); }
  }

  Future<void> _resetUserPassword() async {
    if (widget.screenKey != 'users' || _selectedId == null) return;
    final password = TextEditingController();
    final confirm = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('إعادة تعيين كلمة المرور'),
      content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور الجديدة')),
        const SizedBox(height: 12),
        TextField(controller: confirm, obscureText: true, decoration: const InputDecoration(labelText: 'تأكيد كلمة المرور')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد'))],
    ));
    if (ok != true || !mounted) { password.dispose(); confirm.dispose(); return; }
    if (password.text.trim().length < 6 || password.text != confirm.text) { _message('كلمتا المرور يجب أن تتطابقا وألا تقل كلمة المرور عن 6 أحرف'); password.dispose(); confirm.dispose(); return; }
    try {
      final hash = sha256.convert(utf8.encode(password.text)).toString();
      await DatabaseHelper.instance.update('users', {'password_hash': hash}, where: 'id = ?', whereArgs: [_selectedId]);
      _message('تمت إعادة تعيين كلمة المرور');
    } catch (e) { _message('تعذرت إعادة تعيين كلمة المرور: $e'); }
    password.dispose(); confirm.dispose();
  }

  Future<void> _printSelected() async {
    if (_selectedId == null) { _message('حدد فاتورة من الجدول أولاً'); return; }
    final rows = await DatabaseHelper.instance.query(config.table, where: 'id = ?', whereArgs: [_selectedId], limit: 1);
    if (rows.isEmpty || !mounted) return;
    final header = rows.first;
    final lineTable = _lineTable;
    final lines = lineTable == null ? <Map<String,Object?>>[] : await DatabaseHelper.instance.query(lineTable, where: '$_lineParent = ?', whereArgs: [_selectedId]);
    if (!mounted) return;
    await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: Text('معاينة ${config.title} — ${header['invoice_no'] ?? header['return_no'] ?? _selectedId}'),
      content: SizedBox(width: 620, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('التاريخ: ${header['invoice_date'] ?? header['return_date'] ?? '—'}'),
        Text('الحالة: ${header['status'] ?? 'مسودة'}'),
        const Divider(),
        if (lines.isEmpty) const Text('لا توجد بنود للعرض.') else ...lines.map((line) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('الصنف #${line['product_id'] ?? '—'} | الكمية: ${line['qty'] ?? '—'} | السعر: ${line['price'] ?? line['cost'] ?? '—'} | الإجمالي: ${line['line_total'] ?? '—'}'))),
        const Divider(),
        Text('الإجمالي: ${header['subtotal'] ?? header['total'] ?? 0}'),
        Text('الخصم: ${header['discount'] ?? 0}   الضريبة: ${header['tax'] ?? 0}'),
        Text('الصافي: ${header['net'] ?? header['total'] ?? 0}   المدفوع: ${header['paid'] ?? 0}'),
      ]))),
      actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق'))],
    ));
  }

  Future<void> _delete(Map<String,Object?> row) async {
    if (widget.screenKey == 'users') {
      final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('تعطيل المستخدم'), content: const Text('سيتم تعطيل المستخدم منطقيًا مع الاحتفاظ بسجله. هل تريد المتابعة؟'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تعطيل'))]));
      if (yes != true || !mounted) return;
      try { await DatabaseHelper.instance.update('users', {'is_active': 0}, where: 'id = ?', whereArgs: [row['id']]); if (_selectedId == row['id']) _clear(); await context.read<AppProvider>().refresh(); _message('تم تعطيل المستخدم دون حذف سجله'); } catch (e) { _message('تعذر تعطيل المستخدم: $e'); }
      return;
    }
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
      _controllers[field]!.text = (field == 'password_hash' || field == 'confirm_password') ? '' : (row[field] ?? '').toString(); 
    }
    if (widget.screenKey == 'backup') _restorePathController.text = (row['file_path'] ?? '').toString();
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

  Future<void> _runDailyBackupIfDue() async {
    if (!mounted || _busy || !_dailyBackupEnabled) return;
    final match = RegExp(r'^(\\d{2}):(\\d{2})
    final docs = await getApplicationDocumentsDirectory();
    final defaultFolder = p.join(docs.path, 'StoreERP', 'backups');
    final settings = await DatabaseHelper.instance.query('app_settings');
    final values = <String,String>{
      for (final row in settings) (row['key'] ?? '').toString(): (row['value'] ?? '').toString(),
    };
    if (!mounted) return;
    setState(() {
      _backupFolderController.text = values['backup_folder'] ?? defaultFolder;
      _backupNameController.text = values['backup_file_name'] ?? 'store_backup';
      _verifyBackup = values['backup_verify'] != 'false';
      _safetyCopyBeforeRestore = values['backup_safety_copy'] != 'false';
      _dailyBackupEnabled = values['backup_daily_enabled'] == 'true';
      _backupTimeController.text = values['backup_daily_time'] ?? '22:00';
    });
  }

  Future<void> _saveBackupSettings() async {
    final folder = _backupFolderController.text.trim();
    if (folder.isEmpty) { _message('حدد مجلد حفظ النسخ'); return; }
    final values = <String,String>{
      'backup_folder': folder,
      'backup_file_name': _backupNameController.text.trim().isEmpty ? 'store_backup' : _backupNameController.text.trim(),
      'backup_verify': '$_verifyBackup',
      'backup_safety_copy': '$_safetyCopyBeforeRestore',
      'backup_daily_enabled': '$_dailyBackupEnabled',
      'backup_daily_time': _backupTimeController.text.trim(),
    };
    for (final entry in values.entries) {
      final found = await DatabaseHelper.instance.query('app_settings', where: 'key=?', whereArgs: [entry.key], limit: 1);
      if (found.isEmpty) {
        await DatabaseHelper.instance.insert('app_settings', {'key': entry.key, 'value': entry.value});
      } else {
        await DatabaseHelper.instance.update('app_settings', {'value': entry.value}, where: 'key=?', whereArgs: [entry.key]);
      }
    }
    _message('تم حفظ إعدادات النسخ');
  }

  Future<void> _editBackupPath({required bool restore}) async {
    final controller = TextEditingController(text: restore ? _restorePathController.text : _backupFolderController.text);
    final value = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: Text(restore ? 'تحديد ملف النسخة' : 'تحديد مجلد حفظ النسخ'),
      content: SizedBox(width: 520, child: TextField(controller: controller, decoration: InputDecoration(labelText: restore ? 'مسار ملف .db' : 'مسار المجلد'))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('استخدام المسار')),
      ],
    ));
    controller.dispose();
    if (value == null || value.isEmpty || !mounted) return;
    setState(() {
      if (restore) { _restorePathController.text = value; } else { _backupFolderController.text = value; }
    });
  }

  Future<void> _backup() async {
    setState(() => _busy = true);
    String? createdPath;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final folderPath = _backupFolderController.text.trim().isEmpty
          ? p.join(docs.path, 'StoreERP', 'backups')
          : _backupFolderController.text.trim();
      final folder = Directory(folderPath);
      await folder.create(recursive: true);
      await (await DatabaseHelper.instance.database).rawQuery('PRAGMA wal_checkpoint(FULL)');
      final source = await DatabaseHelper.instance.databasePath;
      final stem = (_backupNameController.text.trim().isEmpty ? 'store_backup' : _backupNameController.text.trim())
          .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      createdPath = p.join(folder.path, '${stem}_${DateTime.now().toIso8601String().replaceAll(':','-')}.db');
      await File(source).copy(createdPath);
      var status = 'نجاح — دون تحقق';
      if (_verifyBackup) {
        final file = File(createdPath);
        final handle = await file.open();
        final header = await handle.read(16);
        await handle.close();
        if (header.length != 16 || ascii.decode(header.take(15), allowInvalid: true) != 'SQLite format 3' || header[15] != 0) {
          throw StateError('فشل التحقق من ملف النسخة');
        }
        status = 'نجاح — تم التحقق من ترويسة SQLite';
      }
      if (!mounted) return;
      await context.read<AppProvider>().create('backup_history', {'file_path': createdPath, 'status': status});
      _lastBackupSucceeded = true;
      _message('تم إنشاء النسخة الاحتياطية: $createdPath');
    } catch (e) {
      if (createdPath != null) {
        try { await context.read<AppProvider>().create('backup_history', {'file_path': createdPath, 'status': 'فشل: $e'}); } catch (_) {}
      }
      _lastBackupSucceeded = false;
      _message('فشل إنشاء النسخة الاحتياطية: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreBackup() async {
    final controller = TextEditingController(text: _restorePathController.text);
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
    _restorePathController.text = path;
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
      final safetyDir=Directory(_backupFolderController.text.trim().isEmpty ? p.join(docs.path,'StoreERP','backups') : _backupFolderController.text.trim());
      await safetyDir.create(recursive:true);
      if (_safetyCopyBeforeRestore) await File(target).copy(p.join(safetyDir.path,'pre_restore_${DateTime.now().millisecondsSinceEpoch}.db'));
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

  String _displayValue(String field, Object? value) {
    if (value == null) return '—';
    if (field == 'is_active') {
      return (value as num?)?.toInt() == 1 ? 'نشط' : 'غير نشط';
    }
    final reference = _referenceFields[field];
    final id = (value as num?)?.toInt() ?? int.tryParse(value.toString());
    if (reference != null && id != null) {
      final options = _referenceOptions[field] ?? const <Map<String, Object?>>[];
      for (final option in options) {
        if ((option['id'] as num?)?.toInt() == id) {
          return '${option[reference.$2] ?? value} (#$id)';
        }
      }
    }
    return value.toString();
  }

  Future<List<Map<String, Object?>>> _loadRows() async {
    final rows = await context.read<AppProvider>().load(config.table);
    final expectedType = switch (widget.screenKey) {
      'counts' => 'فعلي',
      'dailycount' => 'يومي',
      'monthlycount' => 'شهري',
      'yearlycount' => 'سنوي',
      _ => null,
    };
    if (expectedType == null) return rows;
    final documents = await DatabaseHelper.instance.query('inventory_documents');
    final matchingIds = documents
        .where((row) => (row['inventory_type'] ?? '').toString().contains(expectedType))
        .map((row) => row['id'])
        .toSet();
    return rows.where((row) => matchingIds.contains(row['document_id'])).toList();
  }

  @override 
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String,Object?>>>(
      future: _loadRows(),
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
              if (!_readOnly) ActionButton(_selectedId == null ? 'حفظ' : 'تحديث', icon: Icons.save, primary: true, onPressed: _busy ? () {} : _save),
              if (!_readOnly) ActionButton('تفريغ', icon: Icons.cleaning_services, onPressed: _clear),
              if (widget.screenKey == 'users' && _selectedId != null) ActionButton('إعادة تعيين كلمة المرور', icon: Icons.password, onPressed: _resetUserPassword),
              if (['sales','purchases','returns'].contains(widget.screenKey)) ActionButton('حفظ كمسودة', icon: Icons.drafts_outlined, onPressed: _save),
              if (['sales','purchases','returns'].contains(widget.screenKey)) ActionButton('طباعة / معاينة', icon: Icons.print_outlined, onPressed: _printSelected),
              if (['sales','purchases','returns'].contains(widget.screenKey) && _selectedId != null) ActionButton('الدفعات / التسوية', icon: Icons.payments_outlined, onPressed: _addPayment),
              if (widget.screenKey == 'returns' && _selectedId != null) ActionButton('استدعاء الفاتورة الأصلية', icon: Icons.receipt_long_outlined, onPressed: _loadOriginalInvoice),
              if (['sales','purchases'].contains(widget.screenKey)) ActionButton('فاتورة جديدة', icon: Icons.note_add_outlined, onPressed: _clear),
            ]), 
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, 
              children: [
                if (widget.screenKey == 'sales' || widget.screenKey == 'purchases') Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('الكاشير: ${context.watch<AppProvider>().currentUser}  •  الصندوق المحدد هو جلسة التحصيل الحالية', style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.blueGrey))),
                if (widget.screenKey == 'sales' || widget.screenKey == 'purchases') const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('احفظ رأس الفاتورة ثم حدده، وأضف البنود من زر «إضافة بند». تظل الفاتورة مسودة حتى تنفيذ الترحيل والتحقق من المخزون والحسابات.', style: TextStyle(color: Colors.deepOrange))),
                if (widget.screenKey == 'returns') const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('أدخل معرف فاتورة البيع الأصلية، ثم احفظ رأس المرتجع وأضف الأصناف المرتجعة من زر «إضافة بند».', style: TextStyle(color: Colors.deepOrange))),
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
          
          if (widget.screenKey == 'backup') ...[
            const SizedBox(height: 12),
            SectionCard(
              title: 'إعدادات النسخ الاحتياطي والاسترجاع',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('قاعدة البيانات محلية بصيغة SQLite؛ النسخ اليومي لا يعمل عندما يكون التطبيق مغلقًا.'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(width: 420, child: TextField(controller: _backupFolderController, decoration: const InputDecoration(labelText: 'مجلد الحفظ الافتراضي'))),
                      ActionButton('استعراض المجلد', icon: Icons.folder_open, onPressed: () => _editBackupPath(restore: false)),
                      SizedBox(width: 280, child: TextField(controller: _backupNameController, decoration: const InputDecoration(labelText: 'اسم ملف النسخة'))),
                      ActionButton('حفظ الإعدادات', icon: Icons.save_outlined, onPressed: _saveBackupSettings),
                    ],
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: _verifyBackup,
                    onChanged: (value) => setState(() => _verifyBackup = value ?? true),
                    title: const Text('التحقق من ملف النسخة بعد الإنشاء'),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                  CheckboxListTile(
                    value: _safetyCopyBeforeRestore,
                    onChanged: (value) => setState(() => _safetyCopyBeforeRestore = value ?? true),
                    title: const Text('إنشاء نسخة أمان قبل الاسترجاع'),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionButton('اختيار ملف الاسترجاع', icon: Icons.folder_open, onPressed: () => _editBackupPath(restore: true)),
                      ActionButton('بدء الاسترجاع', icon: Icons.settings_backup_restore, onPressed: _restoreBackup),
                    ],
                  ),
                  if (_restorePathController.text.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(top: 8), child: SelectableText('ملف الاسترجاع المحدد: ${_restorePathController.text}')),
                ],
              ),
            ),
          ],
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
                                      ...keys.map((k) => DataCell(Text(_displayValue(k, r[k])))),
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
          
          if (_selectedId != null && ['sales','purchases'].contains(widget.screenKey)) ...[
            const SizedBox(height: 12),
            Builder(builder: (context) {
              final selectedRows = all.where((row) => row['id'] == _selectedId).toList();
              final h = selectedRows.isEmpty ? <String,Object?>{} : selectedRows.first;
              final subtotal = (h['subtotal'] as num?)?.toDouble() ?? 0;
              final discount = (h['discount'] as num?)?.toDouble() ?? 0;
              final tax = (h['tax'] as num?)?.toDouble() ?? 0;
              final net = (h['net'] as num?)?.toDouble() ?? 0;
              final paid = (h['paid'] as num?)?.toDouble() ?? 0;
              final remaining = (net - paid).clamp(0, double.infinity).toDouble();
              Widget metric(String label, double value) => Container(padding: const EdgeInsets.all(12), constraints: const BoxConstraints(minWidth: 130), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: Theme.of(context).textTheme.labelMedium), const SizedBox(height: 4), Text(value.toStringAsFixed(2), style: Theme.of(context).textTheme.titleMedium)]));
              return SectionCard(title: 'الملخص المالي', child: Wrap(spacing: 10, runSpacing: 10, children: [metric('الإجمالي', subtotal), metric('الخصم', discount), metric('الضريبة', tax), metric('الصافي', net), metric('المدفوع', paid), metric('المتبقي', remaining)]));
            }),
          ],
          
          if (_selectedId != null && ['sales','purchases','returns'].contains(widget.screenKey)) ...[
            const SizedBox(height: 12),
            FutureBuilder<List<Map<String,Object?>>>(
              future: DatabaseHelper.instance.query('document_payments', where: 'document_type=? AND document_id=?', whereArgs: [_paymentDocumentType, _selectedId], orderBy: 'id DESC'),
              builder: (context, paymentSnapshot) {
                final paymentRows = paymentSnapshot.data ?? <Map<String,Object?>>[];
                final totalPaid = paymentRows.fold<double>(0, (sum, row) => sum + ((row['amount'] as num?)?.toDouble() ?? 0));
                final headerRows = all.where((row) => row['id'] == _selectedId).toList();
                final header = headerRows.isEmpty ? <String,Object?>{} : headerRows.first;
                final total = ((header['net'] ?? header['total']) as num?)?.toDouble() ?? 0;
                return SectionCard(
                  title: widget.screenKey == 'returns' ? 'تسوية المرتجع' : 'دفعات المستند',
                  trailing: Text('إجمالي الدفعات: ${totalPaid.toStringAsFixed(2)}'),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (widget.screenKey != 'returns') Text('الصافي: ${total.toStringAsFixed(2)}   |   المتبقي: ${(total-totalPaid).clamp(0,double.infinity).toStringAsFixed(2)}'),
                    if (paymentSnapshot.hasError) Text('تعذر تحميل الدفعات: ${paymentSnapshot.error}')
                    else if (paymentRows.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('لا توجد دفعات مسجلة لهذا المستند.'))
                    else SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(
                      columns: const [DataColumn(label: Text('التاريخ')), DataColumn(label: Text('الطريقة')), DataColumn(label: Text('المبلغ')), DataColumn(label: Text('المرجع')), DataColumn(label: Text('ملاحظات')), DataColumn(label: Text('إجراء'))],
                      rows: paymentRows.map((row) => DataRow(cells: [
                        DataCell(Text((row['payment_date'] ?? '—').toString())),
                        DataCell(Text((row['method'] ?? 'نقدي').toString())),
                        DataCell(Text(((row['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2))),
                        DataCell(Text((row['reference'] ?? '—').toString())),
                        DataCell(Text((row['notes'] ?? '—').toString())),
                        DataCell(IconButton(tooltip: 'حذف الدفعة', onPressed: () => _deletePayment(row), icon: const Icon(Icons.delete_outline, color: Colors.red))),
                      ])).toList(),
                    )),
                    Align(alignment: Alignment.centerRight, child: FilledButton.tonalIcon(onPressed: _addPayment, icon: const Icon(Icons.add_card), label: const Text('إضافة دفعة / تسوية'))),
                  ]),
                );
              },
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
                              child: Text(_displayValue(field, row[field]), overflow: TextOverflow.ellipsis)
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
).firstMatch(_backupTimeController.text.trim());
    if (match == null) return;
    final hour = int.tryParse(match.group(1) ?? '');
    final minute = int.tryParse(match.group(2) ?? '');
    if (hour == null || minute == null || hour > 23 || minute > 59) return;
    final now = DateTime.now();
    if (now.hour < hour || (now.hour == hour && now.minute < minute)) return;
    final today = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final rows = await DatabaseHelper.instance.query(
      'app_settings',
      where: 'key=?',
      whereArgs: ['backup_last_run_date'],
      limit: 1,
    );
    if (rows.isNotEmpty && rows.first['value'] == today) return;
    _lastBackupSucceeded = false;
    await _backup();
    if (!_lastBackupSucceeded || !mounted) return;
    final existing = await DatabaseHelper.instance.query(
      'app_settings',
      where: 'key=?',
      whereArgs: ['backup_last_run_date'],
      limit: 1,
    );
    if (existing.isEmpty) {
      await DatabaseHelper.instance.insert('app_settings', {
        'key': 'backup_last_run_date',
        'value': today,
      });
    } else {
      await DatabaseHelper.instance.update(
        'app_settings',
        {'value': today},
        where: 'key=?',
        whereArgs: ['backup_last_run_date'],
      );
    }
  }

  Future<void> _loadBackupSettings() async {
    final docs = await getApplicationDocumentsDirectory();
    final defaultFolder = p.join(docs.path, 'StoreERP', 'backups');
    final settings = await DatabaseHelper.instance.query('app_settings');
    final values = <String,String>{
      for (final row in settings) (row['key'] ?? '').toString(): (row['value'] ?? '').toString(),
    };
    if (!mounted) return;
    setState(() {
      _backupFolderController.text = values['backup_folder'] ?? defaultFolder;
      _backupNameController.text = values['backup_file_name'] ?? 'store_backup';
      _verifyBackup = values['backup_verify'] != 'false';
      _safetyCopyBeforeRestore = values['backup_safety_copy'] != 'false';
      _dailyBackupEnabled = values['backup_daily_enabled'] == 'true';
      _backupTimeController.text = values['backup_daily_time'] ?? '22:00';
    });
  }

  Future<void> _saveBackupSettings() async {
    final folder = _backupFolderController.text.trim();
    if (folder.isEmpty) { _message('حدد مجلد حفظ النسخ'); return; }
    final values = <String,String>{
      'backup_folder': folder,
      'backup_file_name': _backupNameController.text.trim().isEmpty ? 'store_backup' : _backupNameController.text.trim(),
      'backup_verify': '$_verifyBackup',
      'backup_safety_copy': '$_safetyCopyBeforeRestore',
      'backup_daily_enabled': '$_dailyBackupEnabled',
      'backup_daily_time': _backupTimeController.text.trim(),
    };
    for (final entry in values.entries) {
      final found = await DatabaseHelper.instance.query('app_settings', where: 'key=?', whereArgs: [entry.key], limit: 1);
      if (found.isEmpty) {
        await DatabaseHelper.instance.insert('app_settings', {'key': entry.key, 'value': entry.value});
      } else {
        await DatabaseHelper.instance.update('app_settings', {'value': entry.value}, where: 'key=?', whereArgs: [entry.key]);
      }
    }
    _message('تم حفظ إعدادات النسخ');
  }

  Future<void> _editBackupPath({required bool restore}) async {
    final controller = TextEditingController(text: restore ? _restorePathController.text : _backupFolderController.text);
    final value = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: Text(restore ? 'تحديد ملف النسخة' : 'تحديد مجلد حفظ النسخ'),
      content: SizedBox(width: 520, child: TextField(controller: controller, decoration: InputDecoration(labelText: restore ? 'مسار ملف .db' : 'مسار المجلد'))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('استخدام المسار')),
      ],
    ));
    controller.dispose();
    if (value == null || value.isEmpty || !mounted) return;
    setState(() {
      if (restore) { _restorePathController.text = value; } else { _backupFolderController.text = value; }
    });
  }

  Future<void> _backup() async {
    setState(() => _busy = true);
    String? createdPath;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final folderPath = _backupFolderController.text.trim().isEmpty
          ? p.join(docs.path, 'StoreERP', 'backups')
          : _backupFolderController.text.trim();
      final folder = Directory(folderPath);
      await folder.create(recursive: true);
      await (await DatabaseHelper.instance.database).rawQuery('PRAGMA wal_checkpoint(FULL)');
      final source = await DatabaseHelper.instance.databasePath;
      final stem = (_backupNameController.text.trim().isEmpty ? 'store_backup' : _backupNameController.text.trim())
          .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      createdPath = p.join(folder.path, '${stem}_${DateTime.now().toIso8601String().replaceAll(':','-')}.db');
      await File(source).copy(createdPath);
      var status = 'نجاح — دون تحقق';
      if (_verifyBackup) {
        final file = File(createdPath);
        final handle = await file.open();
        final header = await handle.read(16);
        await handle.close();
        if (header.length != 16 || ascii.decode(header.take(15), allowInvalid: true) != 'SQLite format 3' || header[15] != 0) {
          throw StateError('فشل التحقق من ملف النسخة');
        }
        status = 'نجاح — تم التحقق من ترويسة SQLite';
      }
      if (!mounted) return;
      await context.read<AppProvider>().create('backup_history', {'file_path': createdPath, 'status': status});
      _message('تم إنشاء النسخة الاحتياطية: $createdPath');
    } catch (e) {
      if (createdPath != null) {
        try { await context.read<AppProvider>().create('backup_history', {'file_path': createdPath, 'status': 'فشل: $e'}); } catch (_) {}
      }
      _message('فشل إنشاء النسخة الاحتياطية: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreBackup() async {
    final controller = TextEditingController(text: _restorePathController.text);
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
    _restorePathController.text = path;
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
      final safetyDir=Directory(_backupFolderController.text.trim().isEmpty ? p.join(docs.path,'StoreERP','backups') : _backupFolderController.text.trim());
      await safetyDir.create(recursive:true);
      if (_safetyCopyBeforeRestore) await File(target).copy(p.join(safetyDir.path,'pre_restore_${DateTime.now().millisecondsSinceEpoch}.db'));
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

  String _displayValue(String field, Object? value) {
    if (value == null) return '—';
    if (field == 'is_active') {
      return (value as num?)?.toInt() == 1 ? 'نشط' : 'غير نشط';
    }
    final reference = _referenceFields[field];
    final id = (value as num?)?.toInt() ?? int.tryParse(value.toString());
    if (reference != null && id != null) {
      final options = _referenceOptions[field] ?? const <Map<String, Object?>>[];
      for (final option in options) {
        if ((option['id'] as num?)?.toInt() == id) {
          return '${option[reference.$2] ?? value} (#$id)';
        }
      }
    }
    return value.toString();
  }

  Future<List<Map<String, Object?>>> _loadRows() async {
    final rows = await context.read<AppProvider>().load(config.table);
    final expectedType = switch (widget.screenKey) {
      'counts' => 'فعلي',
      'dailycount' => 'يومي',
      'monthlycount' => 'شهري',
      'yearlycount' => 'سنوي',
      _ => null,
    };
    if (expectedType == null) return rows;
    final documents = await DatabaseHelper.instance.query('inventory_documents');
    final matchingIds = documents
        .where((row) => (row['inventory_type'] ?? '').toString().contains(expectedType))
        .map((row) => row['id'])
        .toSet();
    return rows.where((row) => matchingIds.contains(row['document_id'])).toList();
  }

  @override 
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String,Object?>>>(
      future: _loadRows(),
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
              if (!_readOnly) ActionButton(_selectedId == null ? 'حفظ' : 'تحديث', icon: Icons.save, primary: true, onPressed: _busy ? () {} : _save),
              if (!_readOnly) ActionButton('تفريغ', icon: Icons.cleaning_services, onPressed: _clear),
              if (widget.screenKey == 'users' && _selectedId != null) ActionButton('إعادة تعيين كلمة المرور', icon: Icons.password, onPressed: _resetUserPassword),
              if (['sales','purchases','returns'].contains(widget.screenKey)) ActionButton('حفظ كمسودة', icon: Icons.drafts_outlined, onPressed: _save),
              if (['sales','purchases','returns'].contains(widget.screenKey)) ActionButton('طباعة / معاينة', icon: Icons.print_outlined, onPressed: _printSelected),
              if (['sales','purchases','returns'].contains(widget.screenKey) && _selectedId != null) ActionButton('الدفعات / التسوية', icon: Icons.payments_outlined, onPressed: _addPayment),
              if (widget.screenKey == 'returns' && _selectedId != null) ActionButton('استدعاء الفاتورة الأصلية', icon: Icons.receipt_long_outlined, onPressed: _loadOriginalInvoice),
              if (['sales','purchases'].contains(widget.screenKey)) ActionButton('فاتورة جديدة', icon: Icons.note_add_outlined, onPressed: _clear),
            ]), 
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, 
              children: [
                if (widget.screenKey == 'sales' || widget.screenKey == 'purchases') Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('الكاشير: ${context.watch<AppProvider>().currentUser}  •  الصندوق المحدد هو جلسة التحصيل الحالية', style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.blueGrey))),
                if (widget.screenKey == 'sales' || widget.screenKey == 'purchases') const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('احفظ رأس الفاتورة ثم حدده، وأضف البنود من زر «إضافة بند». تظل الفاتورة مسودة حتى تنفيذ الترحيل والتحقق من المخزون والحسابات.', style: TextStyle(color: Colors.deepOrange))),
                if (widget.screenKey == 'returns') const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('أدخل معرف فاتورة البيع الأصلية، ثم احفظ رأس المرتجع وأضف الأصناف المرتجعة من زر «إضافة بند».', style: TextStyle(color: Colors.deepOrange))),
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
          
          if (widget.screenKey == 'backup') ...[
            const SizedBox(height: 12),
            SectionCard(
              title: 'إعدادات النسخ الاحتياطي والاسترجاع',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('قاعدة البيانات محلية بصيغة SQLite؛ النسخ اليومي لا يعمل عندما يكون التطبيق مغلقًا.'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(width: 420, child: TextField(controller: _backupFolderController, decoration: const InputDecoration(labelText: 'مجلد الحفظ الافتراضي'))),
                      ActionButton('استعراض المجلد', icon: Icons.folder_open, onPressed: () => _editBackupPath(restore: false)),
                      SizedBox(width: 280, child: TextField(controller: _backupNameController, decoration: const InputDecoration(labelText: 'اسم ملف النسخة'))),
                      ActionButton('حفظ الإعدادات', icon: Icons.save_outlined, onPressed: _saveBackupSettings),
                    ],
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: _verifyBackup,
                    onChanged: (value) => setState(() => _verifyBackup = value ?? true),
                    title: const Text('التحقق من ملف النسخة بعد الإنشاء'),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                  CheckboxListTile(
                    value: _safetyCopyBeforeRestore,
                    onChanged: (value) => setState(() => _safetyCopyBeforeRestore = value ?? true),
                    title: const Text('إنشاء نسخة أمان قبل الاسترجاع'),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionButton('اختيار ملف الاسترجاع', icon: Icons.folder_open, onPressed: () => _editBackupPath(restore: true)),
                      ActionButton('بدء الاسترجاع', icon: Icons.settings_backup_restore, onPressed: _restoreBackup),
                    ],
                  ),
                  if (_restorePathController.text.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(top: 8), child: SelectableText('ملف الاسترجاع المحدد: ${_restorePathController.text}')),
                ],
              ),
            ),
          ],
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
                                      ...keys.map((k) => DataCell(Text(_displayValue(k, r[k])))),
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
          
          if (_selectedId != null && ['sales','purchases'].contains(widget.screenKey)) ...[
            const SizedBox(height: 12),
            Builder(builder: (context) {
              final selectedRows = all.where((row) => row['id'] == _selectedId).toList();
              final h = selectedRows.isEmpty ? <String,Object?>{} : selectedRows.first;
              final subtotal = (h['subtotal'] as num?)?.toDouble() ?? 0;
              final discount = (h['discount'] as num?)?.toDouble() ?? 0;
              final tax = (h['tax'] as num?)?.toDouble() ?? 0;
              final net = (h['net'] as num?)?.toDouble() ?? 0;
              final paid = (h['paid'] as num?)?.toDouble() ?? 0;
              final remaining = (net - paid).clamp(0, double.infinity).toDouble();
              Widget metric(String label, double value) => Container(padding: const EdgeInsets.all(12), constraints: const BoxConstraints(minWidth: 130), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: Theme.of(context).textTheme.labelMedium), const SizedBox(height: 4), Text(value.toStringAsFixed(2), style: Theme.of(context).textTheme.titleMedium)]));
              return SectionCard(title: 'الملخص المالي', child: Wrap(spacing: 10, runSpacing: 10, children: [metric('الإجمالي', subtotal), metric('الخصم', discount), metric('الضريبة', tax), metric('الصافي', net), metric('المدفوع', paid), metric('المتبقي', remaining)]));
            }),
          ],
          
          if (_selectedId != null && ['sales','purchases','returns'].contains(widget.screenKey)) ...[
            const SizedBox(height: 12),
            FutureBuilder<List<Map<String,Object?>>>(
              future: DatabaseHelper.instance.query('document_payments', where: 'document_type=? AND document_id=?', whereArgs: [_paymentDocumentType, _selectedId], orderBy: 'id DESC'),
              builder: (context, paymentSnapshot) {
                final paymentRows = paymentSnapshot.data ?? <Map<String,Object?>>[];
                final totalPaid = paymentRows.fold<double>(0, (sum, row) => sum + ((row['amount'] as num?)?.toDouble() ?? 0));
                final headerRows = all.where((row) => row['id'] == _selectedId).toList();
                final header = headerRows.isEmpty ? <String,Object?>{} : headerRows.first;
                final total = ((header['net'] ?? header['total']) as num?)?.toDouble() ?? 0;
                return SectionCard(
                  title: widget.screenKey == 'returns' ? 'تسوية المرتجع' : 'دفعات المستند',
                  trailing: Text('إجمالي الدفعات: ${totalPaid.toStringAsFixed(2)}'),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (widget.screenKey != 'returns') Text('الصافي: ${total.toStringAsFixed(2)}   |   المتبقي: ${(total-totalPaid).clamp(0,double.infinity).toStringAsFixed(2)}'),
                    if (paymentSnapshot.hasError) Text('تعذر تحميل الدفعات: ${paymentSnapshot.error}')
                    else if (paymentRows.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('لا توجد دفعات مسجلة لهذا المستند.'))
                    else SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(
                      columns: const [DataColumn(label: Text('التاريخ')), DataColumn(label: Text('الطريقة')), DataColumn(label: Text('المبلغ')), DataColumn(label: Text('المرجع')), DataColumn(label: Text('ملاحظات')), DataColumn(label: Text('إجراء'))],
                      rows: paymentRows.map((row) => DataRow(cells: [
                        DataCell(Text((row['payment_date'] ?? '—').toString())),
                        DataCell(Text((row['method'] ?? 'نقدي').toString())),
                        DataCell(Text(((row['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2))),
                        DataCell(Text((row['reference'] ?? '—').toString())),
                        DataCell(Text((row['notes'] ?? '—').toString())),
                        DataCell(IconButton(tooltip: 'حذف الدفعة', onPressed: () => _deletePayment(row), icon: const Icon(Icons.delete_outline, color: Colors.red))),
                      ])).toList(),
                    )),
                    Align(alignment: Alignment.centerRight, child: FilledButton.tonalIcon(onPressed: _addPayment, icon: const Icon(Icons.add_card), label: const Text('إضافة دفعة / تسوية'))),
                  ]),
                );
              },
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
                              child: Text(_displayValue(field, row[field]), overflow: TextOverflow.ellipsis)
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
