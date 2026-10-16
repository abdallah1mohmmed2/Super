import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();
  Database? _db;
  Future<Database> get database async => _db ??= await _open();

  @visibleForTesting
  Future<void> openInMemoryForTesting() async {
    await _db?.close();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 7,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  Future<Database> _open() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    final db = await databaseFactory.openDatabase(p.join(dir.path, 'local_store.db'), options: OpenDatabaseOptions(version: 7, onConfigure: (db) async { await db.execute('PRAGMA foreign_keys = ON'); }, onCreate: _onCreate, onUpgrade: _onUpgrade));
    return db;
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''CREATE TABLE IF NOT EXISTS accounting_entries(id INTEGER PRIMARY KEY AUTOINCREMENT, entry_no TEXT UNIQUE NOT NULL, entry_date TEXT NOT NULL, source_type TEXT NOT NULL, source_id INTEGER NOT NULL, description TEXT, status TEXT NOT NULL DEFAULT 'مرحل', created_at TEXT DEFAULT CURRENT_TIMESTAMP, UNIQUE(source_type, source_id))''');
      await db.execute('''CREATE TABLE IF NOT EXISTS accounting_entry_lines(id INTEGER PRIMARY KEY AUTOINCREMENT, entry_id INTEGER NOT NULL REFERENCES accounting_entries(id) ON DELETE CASCADE, account_code TEXT NOT NULL, account_name TEXT NOT NULL, debit REAL NOT NULL DEFAULT 0, credit REAL NOT NULL DEFAULT 0, CHECK(debit >= 0 AND credit >= 0), CHECK(NOT (debit > 0 AND credit > 0)))''');
      await db.execute('''CREATE TABLE IF NOT EXISTS app_accounts(account_code TEXT PRIMARY KEY, account_name TEXT NOT NULL, account_type TEXT NOT NULL, is_active INTEGER NOT NULL DEFAULT 1)''');
      for (final account in [
        ['1000','الصندوق','أصول'], ['1100','المخزون','أصول'], ['1200','ذمم العملاء','أصول'],
        ['2000','ذمم الموردين','التزامات'], ['3000','رأس المال','حقوق ملكية'], ['4000','إيرادات المبيعات','إيرادات'], ['4100','مردودات المبيعات','إيرادات'],
        ['5000','تكلفة البضاعة المباعة','مصروفات'], ['5100','مصروفات التالف','مصروفات']
      ]) {
        await db.insert('app_accounts', {'account_code':account[0], 'account_name':account[1], 'account_type':account[2]}, conflictAlgorithm:ConflictAlgorithm.ignore);
      }
    }
    if (oldVersion < 3) {
      await db.execute('''CREATE TABLE IF NOT EXISTS daily_closings(id INTEGER PRIMARY KEY AUTOINCREMENT, close_date TEXT NOT NULL UNIQUE, sales_total REAL NOT NULL DEFAULT 0, sales_paid REAL NOT NULL DEFAULT 0, purchases_total REAL NOT NULL DEFAULT 0, cash_total REAL NOT NULL DEFAULT 0, closed_by TEXT, created_at TEXT DEFAULT CURRENT_TIMESTAMP)''');
    }
    if (oldVersion < 4) {
      final productColumns = await db.rawQuery('PRAGMA table_info(products)');
      if (!productColumns.any((column) => column['name'] == 'sale_method')) {
        await db.execute("ALTER TABLE products ADD COLUMN sale_method TEXT NOT NULL DEFAULT 'قطعة'");
      }
      final customerColumns = await db.rawQuery('PRAGMA table_info(customers)');
      if (!customerColumns.any((column) => column['name'] == 'manager_approval')) {
        await db.execute('ALTER TABLE customers ADD COLUMN manager_approval INTEGER NOT NULL DEFAULT 0');
      }
    }
    if (oldVersion < 6) {
      final purchaseColumns = await db.rawQuery('PRAGMA table_info(purchases_header)');
      if (!purchaseColumns.any((column) => column['name'] == 'payment_method')) {
        await db.execute("ALTER TABLE purchases_header ADD COLUMN payment_method TEXT DEFAULT 'نقدي'");
      }
      final lineColumns = await db.rawQuery('PRAGMA table_info(purchases_lines)');
      if (!lineColumns.any((column) => column['name'] == 'production_date')) {
        await db.execute('ALTER TABLE purchases_lines ADD COLUMN production_date TEXT');
      }
    }
    if (oldVersion < 5) {
      await db.execute('''CREATE TABLE IF NOT EXISTS document_payments(id INTEGER PRIMARY KEY AUTOINCREMENT, document_type TEXT NOT NULL, document_id INTEGER NOT NULL, payment_date TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, method TEXT NOT NULL DEFAULT 'نقدي', amount REAL NOT NULL CHECK(amount > 0), reference TEXT, notes TEXT)''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_document_payments_parent ON document_payments(document_type, document_id)');
    }
    if (oldVersion < 7) {
      final batchColumns = await db.rawQuery('PRAGMA table_info(product_batches)');
      if (!batchColumns.any((column) => column['name'] == 'production_date')) {
        await db.execute('ALTER TABLE product_batches ADD COLUMN production_date TEXT');
      }
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    final statements = <String>[
      '''CREATE TABLE users(id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT UNIQUE NOT NULL, full_name TEXT NOT NULL, password_hash TEXT NOT NULL, roles TEXT NOT NULL DEFAULT 'مدير نظام', is_active INTEGER NOT NULL DEFAULT 1, created_at TEXT DEFAULT CURRENT_TIMESTAMP)''',
      '''CREATE TABLE categories(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE NOT NULL)''',
      '''CREATE TABLE products(id INTEGER PRIMARY KEY AUTOINCREMENT, code TEXT UNIQUE, name TEXT NOT NULL, english_name TEXT, category_id INTEGER REFERENCES categories(id), unit TEXT DEFAULT 'قطعة', sale_method TEXT NOT NULL DEFAULT 'قطعة', cost_price REAL NOT NULL DEFAULT 0, sale_price REAL NOT NULL DEFAULT 0, stock_tracking INTEGER DEFAULT 1, negative_stock INTEGER DEFAULT 0, is_active INTEGER DEFAULT 1, notes TEXT)''',
      '''CREATE TABLE product_units(id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE, unit_name TEXT NOT NULL, factor REAL NOT NULL DEFAULT 1, sale_price REAL DEFAULT 0)''',
      '''CREATE TABLE barcodes(id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE, unit_id INTEGER REFERENCES product_units(id) ON DELETE SET NULL, barcode TEXT UNIQUE NOT NULL)''',
      '''CREATE TABLE customers(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, code TEXT, phone TEXT, mobile TEXT, address TEXT, credit_limit REAL DEFAULT 0, balance REAL DEFAULT 0, is_active INTEGER DEFAULT 1, is_suspended INTEGER DEFAULT 0, manager_approval INTEGER NOT NULL DEFAULT 0)''',
      '''CREATE TABLE suppliers(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, code TEXT, phone TEXT, mobile TEXT, address TEXT, tax_number TEXT, contact_person TEXT, balance REAL DEFAULT 0, is_active INTEGER DEFAULT 1, notes TEXT)''',
      '''CREATE TABLE warehouses(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE NOT NULL, is_active INTEGER DEFAULT 1)''',
      '''CREATE TABLE cash_boxes(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE NOT NULL, balance REAL DEFAULT 0, is_active INTEGER DEFAULT 1)''',
      '''CREATE TABLE inventory(id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER NOT NULL REFERENCES products(id), warehouse_id INTEGER NOT NULL REFERENCES warehouses(id), qty REAL NOT NULL DEFAULT 0, UNIQUE(product_id, warehouse_id))''',
      '''CREATE TABLE sales_header(id INTEGER PRIMARY KEY AUTOINCREMENT, invoice_no TEXT UNIQUE, invoice_date TEXT NOT NULL, customer_id INTEGER REFERENCES customers(id), warehouse_id INTEGER REFERENCES warehouses(id), cash_box_id INTEGER REFERENCES cash_boxes(id), payment_method TEXT DEFAULT 'نقدي', subtotal REAL DEFAULT 0, discount REAL DEFAULT 0, tax REAL DEFAULT 0, net REAL DEFAULT 0, paid REAL DEFAULT 0, status TEXT DEFAULT 'مسودة', notes TEXT)''',
      '''CREATE TABLE sales_lines(id INTEGER PRIMARY KEY AUTOINCREMENT, sales_id INTEGER NOT NULL REFERENCES sales_header(id) ON DELETE CASCADE, product_id INTEGER NOT NULL REFERENCES products(id), unit TEXT, factor REAL DEFAULT 1, qty REAL NOT NULL, price REAL NOT NULL, discount REAL DEFAULT 0, tax REAL DEFAULT 0, line_total REAL NOT NULL)''',
      '''CREATE TABLE purchases_header(id INTEGER PRIMARY KEY AUTOINCREMENT, invoice_no TEXT UNIQUE, external_no TEXT, invoice_date TEXT NOT NULL, supplier_id INTEGER REFERENCES suppliers(id), warehouse_id INTEGER REFERENCES warehouses(id), cash_box_id INTEGER REFERENCES cash_boxes(id), payment_method TEXT DEFAULT 'نقدي', subtotal REAL DEFAULT 0, discount REAL DEFAULT 0, tax REAL DEFAULT 0, net REAL DEFAULT 0, paid REAL DEFAULT 0, status TEXT DEFAULT 'مسودة', notes TEXT)''',
      '''CREATE TABLE purchases_lines(id INTEGER PRIMARY KEY AUTOINCREMENT, purchase_id INTEGER NOT NULL REFERENCES purchases_header(id) ON DELETE CASCADE, product_id INTEGER NOT NULL REFERENCES products(id), unit TEXT, factor REAL DEFAULT 1, qty REAL NOT NULL, cost REAL NOT NULL, discount REAL DEFAULT 0, tax REAL DEFAULT 0, batch_no TEXT, production_date TEXT, expiry_date TEXT, line_total REAL NOT NULL)''',
      '''CREATE TABLE sales_returns(id INTEGER PRIMARY KEY AUTOINCREMENT, return_no TEXT UNIQUE, sales_id INTEGER REFERENCES sales_header(id), customer_id INTEGER REFERENCES customers(id), warehouse_id INTEGER REFERENCES warehouses(id), return_date TEXT, total REAL DEFAULT 0, status TEXT DEFAULT 'مسودة', reason TEXT)''',
      '''CREATE TABLE sales_return_lines(id INTEGER PRIMARY KEY AUTOINCREMENT, return_id INTEGER NOT NULL REFERENCES sales_returns(id) ON DELETE CASCADE, product_id INTEGER NOT NULL REFERENCES products(id), qty REAL NOT NULL, price REAL NOT NULL, condition TEXT DEFAULT 'سليم')''',
      '''CREATE TABLE warehouse_transfers(id INTEGER PRIMARY KEY AUTOINCREMENT, transfer_no TEXT UNIQUE, transfer_date TEXT, from_warehouse_id INTEGER REFERENCES warehouses(id), to_warehouse_id INTEGER REFERENCES warehouses(id), status TEXT DEFAULT 'مسودة', notes TEXT)''',
      '''CREATE TABLE warehouse_transfer_lines(id INTEGER PRIMARY KEY AUTOINCREMENT, transfer_id INTEGER NOT NULL REFERENCES warehouse_transfers(id) ON DELETE CASCADE, product_id INTEGER NOT NULL REFERENCES products(id), qty REAL NOT NULL, factor REAL DEFAULT 1, unit TEXT)''',
      '''CREATE TABLE damage_documents(id INTEGER PRIMARY KEY AUTOINCREMENT, document_no TEXT UNIQUE, document_date TEXT, warehouse_id INTEGER REFERENCES warehouses(id), document_type TEXT, cause TEXT, status TEXT DEFAULT 'مسودة')''',
      '''CREATE TABLE damage_lines(id INTEGER PRIMARY KEY AUTOINCREMENT, document_id INTEGER NOT NULL REFERENCES damage_documents(id) ON DELETE CASCADE, product_id INTEGER NOT NULL REFERENCES products(id), qty REAL NOT NULL, estimated_cost REAL DEFAULT 0, batch_no TEXT)''',
      '''CREATE TABLE cash_box_transactions(id INTEGER PRIMARY KEY AUTOINCREMENT, cash_box_id INTEGER NOT NULL REFERENCES cash_boxes(id), transaction_date TEXT DEFAULT CURRENT_TIMESTAMP, type TEXT NOT NULL, amount REAL NOT NULL, reference TEXT, notes TEXT)''',
      '''CREATE TABLE cash_transfers(id INTEGER PRIMARY KEY AUTOINCREMENT, transfer_no TEXT UNIQUE, from_cashbox_id INTEGER REFERENCES cash_boxes(id), to_cashbox_id INTEGER REFERENCES cash_boxes(id), amount REAL NOT NULL, reason TEXT, status TEXT DEFAULT 'مسودة', transfer_date TEXT DEFAULT CURRENT_TIMESTAMP)''',
      '''CREATE TABLE inventory_documents(id INTEGER PRIMARY KEY AUTOINCREMENT, document_no TEXT UNIQUE, inventory_date TEXT, warehouse_id INTEGER REFERENCES warehouses(id), inventory_type TEXT, status TEXT DEFAULT 'مسودة', created_by INTEGER REFERENCES users(id), approved_by INTEGER REFERENCES users(id), posted_by INTEGER REFERENCES users(id))''',
      '''CREATE TABLE inventory_items(id INTEGER PRIMARY KEY AUTOINCREMENT, document_id INTEGER NOT NULL REFERENCES inventory_documents(id) ON DELETE CASCADE, product_id INTEGER NOT NULL REFERENCES products(id), book_qty REAL DEFAULT 0, count_qty REAL DEFAULT 0, count_qty2 REAL DEFAULT 0, difference REAL DEFAULT 0, difference_cost REAL DEFAULT 0)''',
      '''CREATE TABLE app_settings(key TEXT PRIMARY KEY, value TEXT)''',
      '''CREATE TABLE document_payments(id INTEGER PRIMARY KEY AUTOINCREMENT, document_type TEXT NOT NULL, document_id INTEGER NOT NULL, payment_date TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, method TEXT NOT NULL DEFAULT 'نقدي', amount REAL NOT NULL CHECK(amount > 0), reference TEXT, notes TEXT)''',
      '''CREATE TABLE audit_log(id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER REFERENCES users(id), action TEXT NOT NULL, entity TEXT, entity_id INTEGER, details TEXT, created_at TEXT DEFAULT CURRENT_TIMESTAMP)''',
      '''CREATE TABLE backup_history(id INTEGER PRIMARY KEY AUTOINCREMENT, file_path TEXT NOT NULL, created_at TEXT DEFAULT CURRENT_TIMESTAMP, status TEXT DEFAULT 'نجاح')''',
      '''CREATE TABLE reorder_levels(id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE, warehouse_id INTEGER NOT NULL REFERENCES warehouses(id), minimum REAL DEFAULT 0, maximum REAL DEFAULT 0, UNIQUE(product_id, warehouse_id))''',
      '''CREATE TABLE product_batches(id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER NOT NULL REFERENCES products(id), warehouse_id INTEGER REFERENCES warehouses(id), batch_no TEXT, production_date TEXT, expiry_date TEXT, qty REAL DEFAULT 0)''',
      '''CREATE TABLE accounting_entries(id INTEGER PRIMARY KEY AUTOINCREMENT, entry_no TEXT UNIQUE NOT NULL, entry_date TEXT NOT NULL, source_type TEXT NOT NULL, source_id INTEGER NOT NULL, description TEXT, status TEXT NOT NULL DEFAULT 'مرحل', created_at TEXT DEFAULT CURRENT_TIMESTAMP, UNIQUE(source_type, source_id))''',
      '''CREATE TABLE accounting_entry_lines(id INTEGER PRIMARY KEY AUTOINCREMENT, entry_id INTEGER NOT NULL REFERENCES accounting_entries(id) ON DELETE CASCADE, account_code TEXT NOT NULL, account_name TEXT NOT NULL, debit REAL NOT NULL DEFAULT 0, credit REAL NOT NULL DEFAULT 0, CHECK(debit >= 0 AND credit >= 0), CHECK(NOT (debit > 0 AND credit > 0)))''',
      '''CREATE TABLE app_accounts(account_code TEXT PRIMARY KEY, account_name TEXT NOT NULL, account_type TEXT NOT NULL, is_active INTEGER NOT NULL DEFAULT 1)''',
      '''CREATE TABLE daily_closings(id INTEGER PRIMARY KEY AUTOINCREMENT, close_date TEXT NOT NULL UNIQUE, sales_total REAL NOT NULL DEFAULT 0, sales_paid REAL NOT NULL DEFAULT 0, purchases_total REAL NOT NULL DEFAULT 0, cash_total REAL NOT NULL DEFAULT 0, closed_by TEXT, created_at TEXT DEFAULT CURRENT_TIMESTAMP)''',
    ];
    for (final sql in statements) { await db.execute(sql); }
    await db.execute('CREATE INDEX idx_products_name ON products(name)');
    await db.execute('CREATE INDEX idx_products_code ON products(code)');
    await db.execute('CREATE INDEX idx_inventory_product_warehouse ON inventory(product_id, warehouse_id)');
    await db.execute('CREATE INDEX idx_sales_date ON sales_header(invoice_date)');
    await db.execute('CREATE INDEX idx_purchases_date ON purchases_header(invoice_date)');
    await db.execute('CREATE INDEX idx_document_payments_parent ON document_payments(document_type, document_id)');
    await db.insert('users', {'username':'admin','full_name':'مدير النظام','password_hash':'admin','roles':'مدير نظام','is_active':1});
    await db.insert('warehouses', {'name':'المخزن الرئيسي'});
    await db.insert('cash_boxes', {'name':'الصندوق الرئيسي','balance':0});
    await db.insert('customers', {'name':'عميل نقدي','code':'CASH','credit_limit':0,'balance':0});
    await db.insert('categories', {'name':'عام'});
    await db.insert('app_settings', {'key':'schema_version','value':'1'});
    for (final account in [
      ['1000','الصندوق','أصول'], ['1100','المخزون','أصول'], ['1200','ذمم العملاء','أصول'],
      ['2000','ذمم الموردين','التزامات'], ['3000','رأس المال','حقوق ملكية'],
      ['4000','إيرادات المبيعات','إيرادات'], ['4100','مردودات المبيعات','إيرادات'], ['5000','تكلفة البضاعة المباعة','مصروفات'],
      ['5100','مصروفات التالف','مصروفات']
    ]) {
      await db.insert('app_accounts', {'account_code':account[0], 'account_name':account[1], 'account_type':account[2]});
    }
  }

  Future<String> get databasePath async { final dir = await getApplicationSupportDirectory(); return p.join(dir.path, 'local_store.db'); }

  Future<List<Map<String, Object?>>> query(String table, {String? where, List<Object?>? whereArgs, String? orderBy, int? limit, int? offset}) async => (await database).query(table, where: where, whereArgs: whereArgs, orderBy: orderBy, limit: limit, offset: offset);
  Future<int> insert(String table, Map<String, Object?> values) async => (await database).insert(table, values, conflictAlgorithm: ConflictAlgorithm.abort);
  Future<int> update(String table, Map<String, Object?> values, {required String where, required List<Object?> whereArgs}) async => (await database).update(table, values, where: where, whereArgs: whereArgs);
  Future<int> delete(String table, {required String where, required List<Object?> whereArgs}) async => (await database).delete(table, where: where, whereArgs: whereArgs);


  Future<void> postSale({required int saleId, required int warehouseId, required int cashBoxId, required List<Map<String, num>> lines, required double net, required double paid, int? customerId}) async {
    final db = await database;
    await db.transaction((txn) async {
      final saleRows = await txn.query('sales_header', where: 'id=?', whereArgs: [saleId], limit: 1);
      if (saleRows.isEmpty) throw StateError('فاتورة المبيعات غير موجودة');
      final sale = saleRows.first;
      final saleDate=(sale['invoice_date']?.toString() ?? '').substring(0,10);
      if ((await txn.query('daily_closings', where:'close_date=?', whereArgs:[saleDate], limit:1)).isNotEmpty) throw StateError('اليوم مقفل ولا يقبل ترحيل مستندات جديدة');
      if (sale['status'] == 'مرحل') throw StateError('الفاتورة مرحلة مسبقًا');
      if (lines.isEmpty) throw StateError('لا يمكن ترحيل فاتورة بلا أصناف');
      if (net < 0 || paid < 0 || paid > net) throw StateError('تحقق من الصافي والمبلغ المدفوع');
      double costTotal = 0;
      for (final line in lines) {
        final productId = (line['product_id'] as num).toInt();
        final qty = (line['qty'] as num).toDouble() * ((line['factor'] as num?)?.toDouble() ?? 1);
        if (qty <= 0) throw StateError('كمية الصنف يجب أن تكون أكبر من صفر');
        final products = await txn.query('products', where: 'id=? AND is_active=1', whereArgs: [productId], limit: 1);
        if (products.isEmpty) throw StateError('الصنف غير موجود أو غير نشط: $productId');
        final product = products.first;
        final stockRows = await txn.query('inventory', where: 'product_id=? AND warehouse_id=?', whereArgs: [productId, warehouseId], limit: 1);
        final stock = stockRows.isEmpty ? 0.0 : (stockRows.first['qty'] as num).toDouble();
        if (stock < qty && (product['negative_stock'] as int? ?? 0) == 0) throw StateError('الرصيد غير كافٍ للصنف ${product['name']}');
        if (stockRows.isEmpty) {
          await txn.insert('inventory', {'product_id':productId,'warehouse_id':warehouseId,'qty':-qty});
        } else {
          await txn.update('inventory', {'qty':stock-qty}, where:'id=?', whereArgs:[stockRows.first['id']]);
        }
        costTotal += qty * ((product['cost_price'] as num?)?.toDouble() ?? 0);
      }
      if(customerId!=null && net>paid) {
        final customers=await txn.query('customers',where:'id=?',whereArgs:[customerId],limit:1);
        if(customers.isEmpty) throw StateError('العميل المحدد غير موجود');
        final customer=customers.first;
        if((customer['is_suspended'] as int? ?? 0)==1) throw StateError('حساب العميل موقوف');
        final limit=(customer['credit_limit'] as num?)?.toDouble() ?? 0;
        final balance=(customer['balance'] as num?)?.toDouble() ?? 0;
        if(limit>0 && balance+(net-paid)>limit) throw StateError('تجاوز حد ائتمان العميل');
      }
      await txn.update('sales_header', {'status':'مرحل','net':net,'paid':paid,'warehouse_id':warehouseId,'cash_box_id':cashBoxId,'customer_id':customerId}, where:'id=?', whereArgs:[saleId]);
      if (paid > 0) {
        await txn.insert('cash_box_transactions', {'cash_box_id':cashBoxId,'type':'مبيعات','amount':paid,'reference':'SALE-$saleId'});
        await txn.rawUpdate('UPDATE cash_boxes SET balance = balance + ? WHERE id=?',[paid,cashBoxId]);
      }
      if (customerId != null && net > paid) await txn.rawUpdate('UPDATE customers SET balance = balance + ? WHERE id=?',[net-paid,customerId]);
      final entryId = await _createJournal(txn, 'SALE', saleId, sale['invoice_date']?.toString() ?? DateTime.now().toIso8601String().substring(0,10), 'ترحيل فاتورة مبيعات ${sale['invoice_no'] ?? saleId}', [
        ['1000', 'الصندوق', paid, 0],
        ['1200', 'ذمم العملاء', net-paid, 0],
        ['4000', 'إيرادات المبيعات', 0, net],
        ['5000', 'تكلفة البضاعة المباعة', costTotal, 0],
        ['1100', 'المخزون', 0, costTotal],
      ]);
      await txn.insert('audit_log', {'action':'ترحيل فاتورة مبيعات','entity':'sales_header','entity_id':saleId,'details':'قيد محاسبي $entryId'});
    });
  }

  Future<void> postPurchase({required int purchaseId, required int warehouseId, required int cashBoxId, required List<Map<String, Object?>> lines, required double net, required double paid, int? supplierId}) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('purchases_header', where:'id=?', whereArgs:[purchaseId], limit:1);
      if (rows.isEmpty) throw StateError('فاتورة المشتريات غير موجودة');
      final header = rows.first;
      final purchaseDate=(header['invoice_date']?.toString() ?? '').substring(0,10);
      if ((await txn.query('daily_closings', where:'close_date=?', whereArgs:[purchaseDate], limit:1)).isNotEmpty) throw StateError('اليوم مقفل ولا يقبل ترحيل مستندات جديدة');
      if (header['status'] == 'مرحل') throw StateError('فاتورة المشتريات مرحلة مسبقًا');
      if (lines.isEmpty) throw StateError('أضف صنفًا واحدًا على الأقل');
      if (net < 0 || paid < 0 || paid > net) throw StateError('تحقق من صافي الفاتورة والمدفوع');
      for (final line in lines) {
        final productId = (line['product_id'] as num).toInt();
        final factor = (line['factor'] as num?)?.toDouble() ?? 1;
        final qty = (line['qty'] as num).toDouble() * factor;
        if (factor <= 0 || qty <= 0) throw StateError('الكمية ومعامل تحويل الوحدة يجب أن يكونا أكبر من صفر');
        final cost = ((line['cost'] as num?)?.toDouble() ?? 0);
        if (cost < 0) throw StateError('التكلفة لا يمكن أن تكون سالبة');
        final products = await txn.query('products', where:'id=?', whereArgs:[productId], limit:1);
        if (products.isEmpty) throw StateError('الصنف غير موجود: $productId');
        final inventory = await txn.query('inventory', where:'product_id=? AND warehouse_id=?', whereArgs:[productId,warehouseId], limit:1);
        if (inventory.isEmpty) {
          await txn.insert('inventory', {'product_id':productId,'warehouse_id':warehouseId,'qty':qty});
        } else {
          final oldQty = (inventory.first['qty'] as num).toDouble();
          await txn.update('inventory', {'qty':oldQty+qty}, where:'id=?', whereArgs:[inventory.first['id']]);
        }
        // The entered cost is per selected unit; normalize it to the product's base unit.
        await txn.update('products', {'cost_price':cost / factor}, where:'id=?', whereArgs:[productId]);
        final batchNo = (line['batch_no'] ?? '').toString().trim();
        final productionDate = (line['production_date'] ?? '').toString().trim();
        final expiryDate = (line['expiry_date'] ?? '').toString().trim();
        if (batchNo.isNotEmpty || productionDate.isNotEmpty || expiryDate.isNotEmpty) {
          final batches = await txn.query(
            'product_batches',
            where: 'product_id=? AND warehouse_id=? AND COALESCE(batch_no, \'\')=?',
            whereArgs: [productId, warehouseId, batchNo],
          );
          final existingBatch = batches.where((batch) =>
            (batch['production_date'] ?? '').toString() == productionDate &&
            (batch['expiry_date'] ?? '').toString() == expiryDate
          ).toList();
          if (existingBatch.isNotEmpty) {
            final oldBatchQty = (existingBatch.first['qty'] as num?)?.toDouble() ?? 0;
            await txn.update('product_batches', {'qty': oldBatchQty + qty}, where: 'id=?', whereArgs: [existingBatch.first['id']]);
          } else {
            await txn.insert('product_batches', {
              'product_id': productId,
              'warehouse_id': warehouseId,
              'batch_no': batchNo.isEmpty ? null : batchNo,
              'production_date': productionDate.isEmpty ? null : productionDate,
              'expiry_date': expiryDate.isEmpty ? null : expiryDate,
              'qty': qty,
            });
          }
        }
      }
      await txn.update('purchases_header', {'status':'مرحل','net':net,'paid':paid,'warehouse_id':warehouseId,'cash_box_id':cashBoxId,'supplier_id':supplierId}, where:'id=?', whereArgs:[purchaseId]);
      if (paid > 0) {
        final cashRows=await txn.query('cash_boxes',where:'id=?',whereArgs:[cashBoxId],limit:1);
        if(cashRows.isEmpty) throw StateError('الصندوق المحدد غير موجود');
        if(((cashRows.first['balance'] as num?)?.toDouble() ?? 0)<paid) throw StateError('رصيد الصندوق غير كافٍ لسداد المشتريات');
        await txn.insert('cash_box_transactions', {'cash_box_id':cashBoxId,'type':'مشتريات','amount':-paid,'reference':'PURCHASE-$purchaseId'});
        await txn.rawUpdate('UPDATE cash_boxes SET balance = balance - ? WHERE id=?',[paid,cashBoxId]);
      }
      if (supplierId != null && net > paid) await txn.rawUpdate('UPDATE suppliers SET balance = balance + ? WHERE id=?',[net-paid,supplierId]);
      final entryId = await _createJournal(txn, 'PURCHASE', purchaseId, header['invoice_date']?.toString() ?? DateTime.now().toIso8601String().substring(0,10), 'ترحيل فاتورة مشتريات ${header['invoice_no'] ?? purchaseId}', [
        ['1100', 'المخزون', net, 0],
        ['1000', 'الصندوق/المتحصلات', 0, paid],
        ['2000', 'ذمم الموردين', 0, net-paid],
      ]);
      await txn.insert('audit_log', {'action':'ترحيل فاتورة مشتريات','entity':'purchases_header','entity_id':purchaseId,'details':'قيد محاسبي $entryId'});
    });
  }

  Future<void> postSalesReturn({required int returnId, required List<Map<String, num>> lines}) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('sales_returns', where:'id=?', whereArgs:[returnId], limit:1);
      if (rows.isEmpty) throw StateError('مستند المرتجع غير موجود');
      final h = rows.first;
      if (h['status'] == 'مرحل') throw StateError('المرتجع مرحل مسبقًا');
      final returnDate = (h['return_date']?.toString() ?? '').substring(0, 10);
      if ((await txn.query('daily_closings', where: 'close_date=?', whereArgs: [returnDate], limit: 1)).isNotEmpty) throw StateError('اليوم مقفل ولا يقبل ترحيل مرتجعات جديدة');
      if (lines.isEmpty) throw StateError('أضف أصناف المرتجع');
      final originalId = (h['sales_id'] as num?)?.toInt();
      final warehouseId = (h['warehouse_id'] as num?)?.toInt();
      if (originalId == null || warehouseId == null) throw StateError('حدد فاتورة البيع والمخزن');
      final original = await txn.query('sales_header', where:'id=? AND status=?', whereArgs:[originalId,'مرحل'], limit:1);
      if (original.isEmpty) throw StateError('يجب أن تكون فاتورة البيع الأصلية مرحلة');
      final originalWarehouseId = (original.first['warehouse_id'] as num?)?.toInt();
      if (originalWarehouseId == null || warehouseId != originalWarehouseId) {
        throw StateError('يجب أن يكون مخزن المرتجع هو مخزن فاتورة البيع الأصلية');
      }
      double total = 0, costTotal = 0;
      final requestedByProduct=<int,double>{};
      for(final line in lines){final id=line['product_id']!.toInt();final q=line['qty']!.toDouble();if(q<=0)throw StateError('كمية المرتجع يجب أن تكون أكبر من صفر');requestedByProduct[id]=(requestedByProduct[id]??0)+q;}
      final checkedProducts=<int>{};
      for (final line in lines) {
        final productId = line['product_id']!.toInt(); final qty = line['qty']!.toDouble(); final price = (line['price'] ?? 0).toDouble();
        if (qty <= 0 || price < 0) throw StateError('تحقق من كمية وسعر المرتجع');
        if(checkedProducts.add(productId)) {
          final sold = await txn.rawQuery('SELECT COALESCE(SUM(qty*COALESCE(factor,1)),0) AS qty FROM sales_lines WHERE sales_id=? AND product_id=?',[originalId,productId]);
          final returned = await txn.rawQuery('SELECT COALESCE(SUM(l.qty),0) AS qty FROM sales_return_lines l JOIN sales_returns r ON r.id=l.return_id WHERE r.sales_id=? AND r.status=? AND l.product_id=?',[originalId,'مرحل',productId]);
          final soldQty = (sold.first['qty'] as num).toDouble(); final returnedQty = (returned.first['qty'] as num).toDouble();
          if ((requestedByProduct[productId]??0) > soldQty-returnedQty+0.000001) throw StateError('كمية المرتجع تتجاوز الكمية المباعة للصنف $productId');
        }
        final products = await txn.query('products', where:'id=?', whereArgs:[productId], limit:1);
        if (products.isEmpty) throw StateError('الصنف غير موجود');
        final isGood = (line['good'] ?? 1).toInt() == 1;
        if (isGood) {
          final stock = await txn.query('inventory', where:'product_id=? AND warehouse_id=?', whereArgs:[productId,warehouseId], limit:1);
          if (stock.isEmpty) await txn.insert('inventory', {'product_id':productId,'warehouse_id':warehouseId,'qty':qty});
          else await txn.update('inventory', {'qty':(stock.first['qty'] as num).toDouble()+qty}, where:'id=?', whereArgs:[stock.first['id']]);
          costTotal += qty * ((products.first['cost_price'] as num?)?.toDouble() ?? 0);
        }
        total += qty*price;
      }
      final originalNet=(original.first['net'] as num?)?.toDouble() ?? 0;
      final originalPaid=(original.first['paid'] as num?)?.toDouble() ?? 0;
      final customerId=(original.first['customer_id'] as num?)?.toInt();
      final customerRows=customerId==null? <Map<String,Object?>>[] : await txn.query('customers',where:'id=?',whereArgs:[customerId],limit:1);
      final outstanding=(originalNet-originalPaid).clamp(0,double.infinity).toDouble();
      final currentCustomerBalance=customerRows.isEmpty?0.0:((customerRows.first['balance'] as num?)?.toDouble()??0);
      final dueReduction=customerId==null?0.0:total.clamp(0,outstanding.clamp(0,currentCustomerBalance)).toDouble();
      final cashRefund=total-dueReduction;
      final originalCashBoxId = (original.first['cash_box_id'] as num?)?.toInt();
      if (originalCashBoxId == null) throw StateError('فاتورة البيع الأصلية لا تحتوي على صندوق تسوية');
      final cashRows = await txn.query('cash_boxes', where:'id=?', whereArgs:[originalCashBoxId], limit:1);
      if (cashRows.isEmpty) throw StateError('صندوق فاتورة البيع الأصلية غير موجود');
      final cashId = originalCashBoxId;
      if (((cashRows.first['balance'] as num?)?.toDouble() ?? 0) < cashRefund) throw StateError('رصيد صندوق الفاتورة الأصلية غير كافٍ لصرف الجزء النقدي من المرتجع');
      if(cashRefund>0){
        await txn.rawUpdate('UPDATE cash_boxes SET balance=balance-? WHERE id=?',[cashRefund,cashId]);
        await txn.insert('cash_box_transactions', {'cash_box_id':cashId,'type':'مرتجع مبيعات','amount':-cashRefund,'reference':'RETURN-$returnId'});
      }
      if(customerId!=null && dueReduction>0) await txn.rawUpdate('UPDATE customers SET balance=MAX(0,balance-?) WHERE id=?',[dueReduction,customerId]);
      await txn.update('sales_returns', {'status':'مرحل','total':total}, where:'id=?', whereArgs:[returnId]);
      await _createJournal(txn,'SALES_RETURN',returnId,h['return_date']?.toString() ?? DateTime.now().toIso8601String().substring(0,10),'ترحيل مرتجع مبيعات ${h['return_no'] ?? returnId}',[
        ['4100','مردودات المبيعات',total,0],['1000','الصندوق',0,cashRefund],['1200','تخفيض ذمم العميل',0,dueReduction],['1100','المخزون',costTotal,0],['5000','تكلفة البضاعة المباعة',0,costTotal]
      ]);
      await txn.insert('audit_log', {'action':'ترحيل مرتجع مبيعات','entity':'sales_returns','entity_id':returnId});
    });
  }

  Future<void> transferWarehouse({required int transferId, required List<Map<String, num>> lines}) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('warehouse_transfers', where:'id=?', whereArgs:[transferId], limit:1);
      if (rows.isEmpty) throw StateError('مستند التحويل غير موجود');
      final h = rows.first;
      if (h['status'] == 'مرحل') throw StateError('التحويل مرحل مسبقًا');
      final fromId = (h['from_warehouse_id'] as num?)?.toInt();
      final toId = (h['to_warehouse_id'] as num?)?.toInt();
      if (fromId == null || toId == null || fromId == toId) throw StateError('حدد مخزنين مختلفين');
      if (lines.isEmpty) throw StateError('مستند التحويل بلا أصناف');
      for (final line in lines) {
        final productId = line['product_id']!.toInt();
        final qty = line['qty']!.toDouble() * (line['factor'] ?? 1);
        if (qty <= 0) throw StateError('الكمية يجب أن تكون أكبر من صفر');
        final source = await txn.query('inventory', where:'product_id=? AND warehouse_id=?', whereArgs:[productId,fromId], limit:1);
        final sourceQty = source.isEmpty ? 0.0 : (source.first['qty'] as num).toDouble();
        if (sourceQty < qty) throw StateError('الرصيد غير كافٍ للصنف $productId');
        await txn.update('inventory', {'qty':sourceQty-qty}, where:'id=?', whereArgs:[source.first['id']]);
        final dest = await txn.query('inventory', where:'product_id=? AND warehouse_id=?', whereArgs:[productId,toId], limit:1);
        if (dest.isEmpty) { await txn.insert('inventory', {'product_id':productId,'warehouse_id':toId,'qty':qty}); }
        else { await txn.update('inventory', {'qty':(dest.first['qty'] as num).toDouble()+qty}, where:'id=?', whereArgs:[dest.first['id']]); }
      }
      await txn.update('warehouse_transfers', {'status':'مرحل'}, where:'id=?', whereArgs:[transferId]);
      await txn.insert('audit_log', {'action':'ترحيل تحويل مخزني','entity':'warehouse_transfers','entity_id':transferId});
    });
  }

  Future<void> transferCash({required int transferId}) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('cash_transfers', where:'id=?', whereArgs:[transferId], limit:1);
      if (rows.isEmpty) throw StateError('مستند تحويل الصندوق غير موجود');
      final h = rows.first;
      if (h['status'] == 'مرحل') throw StateError('التحويل مرحل مسبقًا');
      final fromId = (h['from_cashbox_id'] as num?)?.toInt();
      final toId = (h['to_cashbox_id'] as num?)?.toInt();
      final amount = (h['amount'] as num?)?.toDouble() ?? 0;
      if (fromId == null || toId == null || fromId == toId || amount <= 0) throw StateError('بيانات التحويل غير صحيحة');
      final from = await txn.query('cash_boxes', where:'id=?', whereArgs:[fromId], limit:1);
      final to = await txn.query('cash_boxes', where:'id=?', whereArgs:[toId], limit:1);
      if (from.isEmpty || to.isEmpty) throw StateError('الصندوق المصدر أو المستلم غير موجود');
      if (((from.first['balance'] as num?)?.toDouble() ?? 0) < amount) throw StateError('رصيد الصندوق المصدر غير كافٍ');
      await txn.rawUpdate('UPDATE cash_boxes SET balance=balance-? WHERE id=?',[amount,fromId]);
      await txn.rawUpdate('UPDATE cash_boxes SET balance=balance+? WHERE id=?',[amount,toId]);
      await txn.insert('cash_box_transactions', {'cash_box_id':fromId,'type':'تحويل صادر','amount':-amount,'reference':'TRANSFER-$transferId'});
      await txn.insert('cash_box_transactions', {'cash_box_id':toId,'type':'تحويل وارد','amount':amount,'reference':'TRANSFER-$transferId'});
      await txn.update('cash_transfers', {'status':'مرحل'}, where:'id=?', whereArgs:[transferId]);
      await txn.insert('audit_log', {'action':'ترحيل تحويل نقدي','entity':'cash_transfers','entity_id':transferId});
    });
  }

  Future<void> postDamage({required int documentId, required List<Map<String, num>> lines}) async {
    final db = await database;
    await db.transaction((txn) async {
      final docs = await txn.query('damage_documents', where:'id=?', whereArgs:[documentId], limit:1);
      if (docs.isEmpty) throw StateError('مستند التالف غير موجود');
      final h = docs.first;
      if (h['status'] == 'مرحل') throw StateError('مستند التالف مرحل مسبقًا');
      final warehouseId = (h['warehouse_id'] as num?)?.toInt();
      if (warehouseId == null || lines.isEmpty) throw StateError('حدد المخزن والأصناف');
      double totalCost = 0;
      for (final line in lines) {
        final productId = line['product_id']!.toInt();
        final qty = line['qty']!.toDouble();
        if (qty <= 0) throw StateError('كمية التالف يجب أن تكون أكبر من صفر');
        final stocks = await txn.query('inventory', where:'product_id=? AND warehouse_id=?', whereArgs:[productId,warehouseId], limit:1);
        if (stocks.isEmpty || (stocks.first['qty'] as num).toDouble() < qty) throw StateError('رصيد المخزون غير كافٍ للصنف $productId');
        await txn.update('inventory', {'qty':(stocks.first['qty'] as num).toDouble()-qty}, where:'id=?', whereArgs:[stocks.first['id']]);
        final products = await txn.query('products', where:'id=?', whereArgs:[productId], limit:1);
        final cost = (products.first['cost_price'] as num?)?.toDouble() ?? 0;
        totalCost += qty * cost;
      }
      await txn.update('damage_documents', {'status':'مرحل'}, where:'id=?', whereArgs:[documentId]);
      await _createJournal(txn, 'DAMAGE', documentId, h['document_date']?.toString() ?? DateTime.now().toIso8601String().substring(0,10), 'إثبات تالف ${h['document_no'] ?? documentId}', [
        ['5100','مصروفات التالف',totalCost,0], ['1100','المخزون',0,totalCost]
      ]);
      await txn.insert('audit_log', {'action':'ترحيل سند تالف','entity':'damage_documents','entity_id':documentId});
    });
  }

  Future<void> postInventoryCount({required int documentId}) async {
    final db = await database;
    await db.transaction((txn) async {
      final docs = await txn.query('inventory_documents', where:'id=?', whereArgs:[documentId], limit:1);
      if (docs.isEmpty) throw StateError('مستند الجرد غير موجود');
      final h = docs.first;
      if (h['status'] == 'مرحل') throw StateError('مستند الجرد مرحل مسبقًا');
      final warehouseId = (h['warehouse_id'] as num?)?.toInt();
      if (warehouseId == null) throw StateError('حدد المخزن');
      final items = await txn.query('inventory_items', where:'document_id=?', whereArgs:[documentId]);
      if (items.isEmpty) throw StateError('مستند الجرد لا يحتوي على أصناف');
      double adjustmentCost = 0;
      for (final item in items) {
        final productId = (item['product_id'] as num).toInt();
        final countQty = (item['count_qty'] as num?)?.toDouble() ?? 0;
        final stocks = await txn.query('inventory', where:'product_id=? AND warehouse_id=?', whereArgs:[productId,warehouseId], limit:1);
        final bookQty = stocks.isEmpty ? 0.0 : (stocks.first['qty'] as num).toDouble();
        final difference = countQty - bookQty;
        final products = await txn.query('products', where:'id=?', whereArgs:[productId], limit:1);
        if (products.isEmpty) throw StateError('صنف غير موجود: $productId');
        final cost = (products.first['cost_price'] as num?)?.toDouble() ?? 0;
        adjustmentCost += difference * cost;
        if (stocks.isEmpty) { await txn.insert('inventory', {'product_id':productId,'warehouse_id':warehouseId,'qty':countQty}); }
        else { await txn.update('inventory', {'qty':countQty}, where:'id=?', whereArgs:[stocks.first['id']]); }
        await txn.update('inventory_items', {'book_qty':bookQty,'difference':difference,'difference_cost':difference*cost}, where:'id=?', whereArgs:[item['id']]);
      }
      await txn.update('inventory_documents', {'status':'مرحل','posted_by':h['created_by']}, where:'id=?', whereArgs:[documentId]);
      if (adjustmentCost >= 0) {
        await _createJournal(txn,'COUNT',documentId,h['inventory_date']?.toString() ?? DateTime.now().toIso8601String().substring(0,10),'تسوية جرد ${h['document_no'] ?? documentId}',[
          ['1100','المخزون',adjustmentCost,0],['3000','فروقات الجرد',0,adjustmentCost]
        ]);
      } else {
        await _createJournal(txn,'COUNT',documentId,h['inventory_date']?.toString() ?? DateTime.now().toIso8601String().substring(0,10),'تسوية جرد ${h['document_no'] ?? documentId}',[
          ['5100','عجز الجرد',-adjustmentCost,0],['1100','المخزون',0,-adjustmentCost]
        ]);
      }
      await txn.insert('audit_log', {'action':'ترحيل جرد وتسوية أرصدة','entity':'inventory_documents','entity_id':documentId});
    });
  }

  Future<Map<String, Object?>> closeDay(String date, String user) async {
    final db = await database;
    return db.transaction((txn) async {
      final existing = await txn.query('daily_closings', where:'close_date=?', whereArgs:[date], limit:1);
      if (existing.isNotEmpty) throw StateError('تم إقفال هذا اليوم مسبقًا');
      final drafts = await txn.rawQuery("SELECT 'مبيعات' AS kind, COUNT(*) AS n FROM sales_header WHERE invoice_date LIKE ? AND status!='مرحل' UNION ALL SELECT 'مشتريات', COUNT(*) FROM purchases_header WHERE invoice_date LIKE ? AND status!='مرحل'", ['$date%','$date%']);
      final pending = drafts.fold<int>(0,(sum,row)=>sum+((row['n'] as num?)?.toInt() ?? 0));
      if (pending > 0) throw StateError('يوجد $pending مستند مبيعات/مشتريات غير مرحل؛ عالجها قبل الإقفال');
      final sales = await txn.rawQuery("SELECT COALESCE(SUM(net),0) AS total, COALESCE(SUM(paid),0) AS paid FROM sales_header WHERE invoice_date LIKE ? AND status='مرحل'", ['$date%']);
      final purchases = await txn.rawQuery("SELECT COALESCE(SUM(net),0) AS total FROM purchases_header WHERE invoice_date LIKE ? AND status='مرحل'", ['$date%']);
      final cash = await txn.rawQuery('SELECT COALESCE(SUM(balance),0) AS total FROM cash_boxes');
      final salesTotal=(sales.first['total'] as num).toDouble(); final salesPaid=(sales.first['paid'] as num).toDouble();
      final purchasesTotal=(purchases.first['total'] as num).toDouble(); final cashTotal=(cash.first['total'] as num).toDouble();
      await txn.insert('daily_closings', {'close_date':date,'sales_total':salesTotal,'sales_paid':salesPaid,'purchases_total':purchasesTotal,'cash_total':cashTotal,'closed_by':user});
      await txn.insert('audit_log', {'action':'إقفال يومي','entity':'daily_closings','details':'$date; مبيعات=$salesTotal; مشتريات=$purchasesTotal'});
      return {'close_date':date,'sales_total':salesTotal,'sales_paid':salesPaid,'purchases_total':purchasesTotal,'cash_total':cashTotal};
    });
  }

  Future<int> _createJournal(dynamic txn, String sourceType, int sourceId, String date, String description, List<List<Object>> lines) async {
    final existing = await txn.query('accounting_entries', where:'source_type=? AND source_id=?', whereArgs:[sourceType,sourceId], limit:1);
    if (existing.isNotEmpty) throw StateError('يوجد قيد محاسبي سابق لهذه العملية');
    final debit = lines.fold<double>(0, (sum, line) => sum + (line[2] as num).toDouble());
    final credit = lines.fold<double>(0, (sum, line) => sum + (line[3] as num).toDouble());
    if ((debit-credit).abs() > 0.005) throw StateError('القيد المحاسبي غير متوازن: مدين $debit ودائن $credit');
    final entryId = await txn.insert('accounting_entries', {'entry_no':'JE-${DateTime.now().microsecondsSinceEpoch}', 'entry_date':date, 'source_type':sourceType, 'source_id':sourceId, 'description':description});
    for (final line in lines) {
      if ((line[2] as num) == 0 && (line[3] as num) == 0) continue;
      await txn.insert('accounting_entry_lines', {'entry_id':entryId,'account_code':line[0],'account_name':line[1],'debit':line[2],'credit':line[3]});
    }
    return entryId;
  }

  Future<void> close() async { await _db?.close(); _db = null; }
}
