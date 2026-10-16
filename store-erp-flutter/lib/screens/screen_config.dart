class ScreenConfig {
  final String title, table;
  final List<String> fields, columns;
  const ScreenConfig(this.title, this.table, this.fields, this.columns);
}

/// All operational modules are declared centrally so navigation, CRUD forms,
/// search, and tables use one consistent definition.
const screenConfigs = <String, ScreenConfig>{
 'products': ScreenConfig('إدارة الأصناف','products',['code','name','english_name','category_id','unit','cost_price','sale_price','notes'],['id','code','name','unit','cost_price','sale_price','is_active']),
 'customers': ScreenConfig('إدارة العملاء','customers',['name','code','phone','mobile','address','credit_limit','balance'],['id','name','code','mobile','credit_limit','balance','is_active']),
 'suppliers': ScreenConfig('إدارة الموردين','suppliers',['code','name','phone','mobile','address','tax_number','contact_person','balance','is_active','notes'],['id','code','name','phone','mobile','tax_number','contact_person','balance','is_active']),
 'users': ScreenConfig('إدارة المستخدمين','users',['username','full_name','password_hash','confirm_password','roles','is_active'],['id','username','full_name','roles','is_active']),
 'sales': ScreenConfig('فواتير المبيعات','sales_header',['invoice_no','invoice_date','customer_id','warehouse_id','cash_box_id','payment_method','discount','tax','paid','notes'],['id','invoice_no','invoice_date','net','paid','status']),
 'returns': ScreenConfig('مرتجع البيع','sales_returns',['return_no','return_date','sales_id','customer_id','warehouse_id','reason'],['id','return_no','return_date','total','status']),
 'purchases': ScreenConfig('فواتير المشتريات','purchases_header',['invoice_no','external_no','invoice_date','supplier_id','warehouse_id','cash_box_id','discount','tax','paid','notes'],['id','invoice_no','invoice_date','net','paid','status']),
 'inventory': ScreenConfig('أرصدة المخزون','inventory',['product_id','warehouse_id','qty'],['id','product_id','warehouse_id','qty']),
 'transfers': ScreenConfig('تحويل المخازن','warehouse_transfers',['transfer_no','transfer_date','from_warehouse_id','to_warehouse_id','notes'],['id','transfer_no','transfer_date','status','notes']),
 'damage': ScreenConfig('سند التالف والمنتهي','damage_documents',['document_no','document_date','warehouse_id','document_type','cause'],['id','document_no','document_date','document_type','status']),
 'cashboxes': ScreenConfig('إدارة الصناديق','cash_boxes',['name','is_active'],['id','name','balance','is_active']),
 'cashtransfers': ScreenConfig('تحويل الصناديق','cash_transfers',['transfer_no','from_cashbox_id','to_cashbox_id','amount','reason'],['id','transfer_no','from_cashbox_id','to_cashbox_id','amount','status','transfer_date']),
 'countdocs': ScreenConfig('متابعة مستندات الجرد','inventory_documents',['document_no','inventory_date','warehouse_id','inventory_type'],['id','document_no','inventory_date','warehouse_id','inventory_type','status']),
 'counts': ScreenConfig('الجرد الفعلي','inventory_items',['document_id','product_id','count_qty','count_qty2'],['id','document_id','product_id','book_qty','count_qty','count_qty2','difference','difference_cost']),
 'dailycount': ScreenConfig('الجرد اليومي','inventory_items',['document_id','product_id','book_qty','count_qty','difference'],['id','document_id','product_id','book_qty','count_qty','difference']),
 'monthlycount': ScreenConfig('الجرد الشهري','inventory_items',['document_id','product_id','book_qty','count_qty','difference'],['id','document_id','product_id','book_qty','count_qty','difference']),
 'yearlycount': ScreenConfig('الجرد السنوي','inventory_items',['document_id','product_id','book_qty','count_qty','difference'],['id','document_id','product_id','book_qty','count_qty','difference']),
 'countreports': ScreenConfig('تقارير الجرد','inventory_items',['document_id','product_id','book_qty','count_qty','difference_cost'],['id','document_id','product_id','book_qty','count_qty','difference_cost']),
 'reports': ScreenConfig('التقارير العامة','sales_header',['invoice_no','invoice_date','net','paid','status'],['id','invoice_no','invoice_date','net','paid','status']),
 'backup': ScreenConfig('النسخ الاحتياطي والسجل','backup_history',['file_path','status'],['id','file_path','created_at','status']),
 'closing': ScreenConfig('الإقفال اليومي','sales_header',['invoice_no','invoice_date','net','paid','status'],['id','invoice_no','invoice_date','net','paid','status']),
};

const fieldLabels = <String,String>{
 'id':'المعرف','code':'الكود','name':'الاسم','english_name':'الاسم الإنجليزي','category_id':'التصنيف','unit':'الوحدة','cost_price':'سعر التكلفة','sale_price':'سعر البيع','notes':'ملاحظات','phone':'الهاتف','mobile':'الجوال','address':'العنوان','credit_limit':'حد الائتمان','balance':'الرصيد','username':'اسم المستخدم','full_name':'الاسم الكامل','password_hash':'كلمة المرور','confirm_password':'تأكيد كلمة المرور','roles':'الصلاحيات','is_active':'نشط (1/0)','invoice_no':'رقم الفاتورة','invoice_date':'التاريخ (YYYY-MM-DD)','external_no':'رقم فاتورة المورد','subtotal':'الإجمالي قبل الخصم','discount':'الخصم','tax':'الضريبة','net':'الصافي','paid':'المدفوع','status':'الحالة','return_no':'رقم المرتجع','return_date':'تاريخ المرتجع','total':'الإجمالي','reason':'السبب','product_id':'معرف الصنف','warehouse_id':'معرف المخزن','qty':'الكمية','factor':'معامل التحويل','unit_name':'اسم الوحدة','barcode':'الباركود','document_id':'معرف المستند','book_qty':'الرصيد الدفتري','count_qty':'الكمية المعدودة','count_qty2':'العد الثاني','difference':'الفرق','difference_cost':'قيمة الفرق','file_path':'مسار النسخة','created_at':'تاريخ الإنشاء','document_no':'رقم المستند','inventory_type':'نوع الجرد','inventory_date':'تاريخ الجرد (YYYY-MM-DD)','document_type':'نوع المستند','cause':'سبب الإتلاف','amount':'المبلغ','transfer_no':'رقم التحويل','tax_number':'الرقم الضريبي','contact_person':'اسم المسؤول','supplier_id':'معرف المورد','cash_box_id':'معرف الصندوق','sales_id':'معرف فاتورة البيع','customer_id':'معرف العميل','from_warehouse_id':'المخزن المصدر','to_warehouse_id':'المخزن المستلم','from_cashbox_id':'الصندوق المصدر','to_cashbox_id':'الصندوق المستلم','payment_method':'طريقة الدفع'
};
String fieldLabel(String field) => fieldLabels[field] ?? field;
