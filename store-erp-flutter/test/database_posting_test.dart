import 'package:flutter_test/flutter_test.dart';
import 'package:store_erp_flutter/data/database_helper.dart';

void main() {
  final helper = DatabaseHelper.instance;

  setUp(() async {
    await helper.openInMemoryForTesting();
  });

  tearDown(() async {
    await helper.close();
  });

  String today() => DateTime.now().toIso8601String().substring(0, 10);

  Future<int> createProduct({double cost = 4, double price = 10}) async {
    final db = await helper.database;
    return db.insert('products', {
      'name': 'صنف اختبار',
      'cost_price': cost,
      'sale_price': price,
      'is_active': 1,
    });
  }

  Future<int> createOpenSession({int cashBoxId = 1}) async {
    final db = await helper.database;
    return db.insert('cash_sessions', {
      'cash_box_id': cashBoxId,
      'session_no': 'TEST-CS-${DateTime.now().microsecondsSinceEpoch}',
      'opened_at': DateTime.now().toIso8601String(),
      'opening_balance': 0,
      'status': 'مفتوحة',
      'opened_by': 'test',
    });
  }

  Future<void> expectJournalBalanced(String sourceType, int sourceId) async {
    final entries = await helper.query(
      'accounting_entries',
      where: 'source_type=? AND source_id=?',
      whereArgs: [sourceType, sourceId],
    );
    expect(entries, hasLength(1));
    final lines = await helper.query(
      'accounting_entry_lines',
      where: 'entry_id=?',
      whereArgs: [entries.single['id']],
    );
    final debit = lines.fold<double>(
      0,
      (sum, row) => sum + ((row['debit'] as num?)?.toDouble() ?? 0),
    );
    final credit = lines.fold<double>(
      0,
      (sum, row) => sum + ((row['credit'] as num?)?.toDouble() ?? 0),
    );
    expect((debit - credit).abs(), lessThan(0.005));
  }

  test('sales posting updates stock, cash, journal and prevents double posting',
      () async {
    final db = await helper.database;
    final productId = await createProduct();
    await db.insert('inventory', {
      'product_id': productId,
      'warehouse_id': 1,
      'qty': 10,
    });
    final saleId = await db.insert('sales_header', {
      'invoice_no': 'TEST-SALE-1',
      'invoice_date': today(),
      'warehouse_id': 1,
      'cash_box_id': 1,
      'cash_session_id': await createOpenSession(),
      'cashier': 'test',
      'net': 20,
      'paid': 20,
      'status': 'مسودة',
    });
    await db.insert('sales_lines', {
      'sales_id': saleId,
      'product_id': productId,
      'unit': 'قطعة',
      'factor': 1,
      'qty': 2,
      'price': 10,
      'discount': 0,
      'tax': 0,
      'line_total': 20,
    });

    final lines = [
      {'product_id': productId, 'qty': 2.0, 'factor': 1.0},
    ];
    await helper.postSale(
      saleId: saleId,
      warehouseId: 1,
      cashBoxId: 1,
      lines: lines,
      net: 20,
      paid: 20,
    );

    var stock = await helper.query(
      'inventory',
      where: 'product_id=? AND warehouse_id=?',
      whereArgs: [productId, 1],
    );
    var cashBoxes = await helper.query('cash_boxes', where: 'id=?', whereArgs: [1]);
    var sales = await helper.query('sales_header', where: 'id=?', whereArgs: [saleId]);
    expect((stock.single['qty'] as num).toDouble(), 8);
    expect((cashBoxes.single['balance'] as num).toDouble(), 20);
    expect(sales.single['status'], 'مرحل');
    await expectJournalBalanced('SALE', saleId);

    await expectLater(
      helper.postSale(
        saleId: saleId,
        warehouseId: 1,
        cashBoxId: 1,
        lines: lines,
        net: 20,
        paid: 20,
      ),
      throwsA(isA<StateError>()),
    );
    stock = await helper.query(
      'inventory',
      where: 'product_id=? AND warehouse_id=?',
      whereArgs: [productId, 1],
    );
    cashBoxes = await helper.query('cash_boxes', where: 'id=?', whereArgs: [1]);
    expect((stock.single['qty'] as num).toDouble(), 8);
    expect((cashBoxes.single['balance'] as num).toDouble(), 20);
  });

  test('purchase posting normalizes selected-unit cost and receives stock',
      () async {
    final db = await helper.database;
    final productId = await createProduct(cost: 2, price: 10);
    final supplierId = await db.insert('suppliers', {'name': 'مورد اختبار'});
    final purchaseId = await db.insert('purchases_header', {
      'invoice_no': 'TEST-PURCHASE-1',
      'invoice_date': today(),
      'supplier_id': supplierId,
      'warehouse_id': 1,
      'cash_box_id': 1,
      'net': 100,
      'paid': 0,
      'status': 'مسودة',
    });
    await db.insert('purchases_lines', {
      'purchase_id': purchaseId,
      'product_id': productId,
      'unit': 'كرتون',
      'factor': 10,
      'qty': 2,
      'cost': 50,
      'discount': 0,
      'tax': 0,
      'batch_no': 'BATCH-1',
      'production_date': '2026-01-01',
      'expiry_date': '2027-01-01',
      'line_total': 100,
    });

    await helper.postPurchase(
      purchaseId: purchaseId,
      warehouseId: 1,
      cashBoxId: 1,
      supplierId: supplierId,
      net: 100,
      paid: 0,
      lines: [
        {
          'product_id': productId,
          'qty': 2,
          'factor': 10,
          'cost': 50,
          'batch_no': 'BATCH-1',
          'production_date': '2026-01-01',
          'expiry_date': '2027-01-01',
        },
      ],
    );

    final stock = await helper.query(
      'inventory',
      where: 'product_id=? AND warehouse_id=?',
      whereArgs: [productId, 1],
    );
    final products = await helper.query('products', where: 'id=?', whereArgs: [productId]);
    final suppliers = await helper.query('suppliers', where: 'id=?', whereArgs: [supplierId]);
    final batches = await helper.query(
      'product_batches',
      where: 'product_id=? AND warehouse_id=?',
      whereArgs: [productId, 1],
    );
    expect((stock.single['qty'] as num).toDouble(), 20);
    expect((products.single['cost_price'] as num).toDouble(), 5);
    expect((suppliers.single['balance'] as num).toDouble(), 100);
    expect(batches.single['production_date'], '2026-01-01');
    await expectJournalBalanced('PURCHASE', purchaseId);
  });

  test('sales return restores good stock and refunds the original cash box',
      () async {
    final db = await helper.database;
    final productId = await createProduct(cost: 4, price: 10);
    await db.insert('inventory', {
      'product_id': productId,
      'warehouse_id': 1,
      'qty': 10,
    });
    final otherCashBoxId = await db.insert('cash_boxes', {
      'name': 'صندوق آخر',
      'balance': 100,
      'is_active': 1,
    });
    final saleId = await db.insert('sales_header', {
      'invoice_no': 'TEST-SALE-RETURN-1',
      'invoice_date': today(),
      'customer_id': 1,
      'warehouse_id': 1,
      'cash_box_id': 1,
      'cash_session_id': await createOpenSession(),
      'cashier': 'test',
      'net': 20,
      'paid': 20,
      'status': 'مسودة',
    });
    await db.insert('sales_lines', {
      'sales_id': saleId,
      'product_id': productId,
      'unit': 'قطعة',
      'factor': 1,
      'qty': 2,
      'price': 10,
      'discount': 0,
      'tax': 0,
      'line_total': 20,
    });
    await helper.postSale(
      saleId: saleId,
      warehouseId: 1,
      cashBoxId: 1,
      customerId: 1,
      lines: [
        {'product_id': productId, 'qty': 2.0, 'factor': 1.0},
      ],
      net: 20,
      paid: 20,
    );

    final returnId = await db.insert('sales_returns', {
      'return_no': 'TEST-RETURN-1',
      'sales_id': saleId,
      'customer_id': 1,
      'warehouse_id': 1,
      'return_date': today(),
      'total': 10,
      'status': 'مسودة',
      'reason': 'اختبار',
    });
    await db.insert('sales_return_lines', {
      'return_id': returnId,
      'product_id': productId,
      'qty': 1,
      'price': 10,
      'condition': 'سليم',
    });

    await helper.postSalesReturn(
      returnId: returnId,
      lines: [
        {'product_id': productId, 'qty': 1.0, 'price': 10.0, 'good': 1.0},
      ],
    );

    final stock = await helper.query(
      'inventory',
      where: 'product_id=? AND warehouse_id=?',
      whereArgs: [productId, 1],
    );
    final originalCashBox = await helper.query('cash_boxes', where: 'id=?', whereArgs: [1]);
    final otherCashBox = await helper.query('cash_boxes', where: 'id=?', whereArgs: [otherCashBoxId]);
    final returns = await helper.query('sales_returns', where: 'id=?', whereArgs: [returnId]);
    expect((stock.single['qty'] as num).toDouble(), 9);
    expect((originalCashBox.single['balance'] as num).toDouble(), 10);
    expect((otherCashBox.single['balance'] as num).toDouble(), 100);
    expect(returns.single['status'], 'مرحل');
    await expectJournalBalanced('SALES_RETURN', returnId);
  });

  test('return can settle to customer credit without creating a negative balance',
      () async {
    final db = await helper.database;
    final productId = await createProduct(cost: 4, price: 10);
    await db.insert('inventory', {
      'product_id': productId,
      'warehouse_id': 1,
      'qty': 5,
    });
    final saleId = await db.insert('sales_header', {
      'invoice_no': 'TEST-CREDIT-SALE-1',
      'invoice_date': today(),
      'customer_id': 1,
      'warehouse_id': 1,
      'cash_box_id': 1,
      'cash_session_id': await createOpenSession(),
      'cashier': 'test',
      'net': 20,
      'paid': 0,
      'status': 'مسودة',
    });
    await db.insert('sales_lines', {
      'sales_id': saleId,
      'product_id': productId,
      'unit': 'قطعة',
      'factor': 1,
      'qty': 2,
      'price': 10,
      'discount': 0,
      'tax': 0,
      'line_total': 20,
    });
    await helper.postSale(
      saleId: saleId,
      warehouseId: 1,
      cashBoxId: 1,
      customerId: 1,
      lines: [
        {'product_id': productId, 'qty': 2.0, 'factor': 1.0},
      ],
      net: 20,
      paid: 0,
    );

    final returnId = await db.insert('sales_returns', {
      'return_no': 'TEST-CREDIT-RETURN-1',
      'sales_id': saleId,
      'customer_id': 1,
      'warehouse_id': 1,
      'return_date': today(),
      'total': 10,
      'status': 'مسودة',
      'reason': 'اختبار تسوية على الرصيد',
    });
    await db.insert('sales_return_lines', {
      'return_id': returnId,
      'product_id': productId,
      'qty': 1,
      'price': 10,
      'condition': 'سليم',
    });
    await db.insert('document_payments', {
      'document_type': 'returns',
      'document_id': returnId,
      'payment_date': today(),
      'method': 'على الرصيد',
      'amount': 10,
    });

    await helper.postSalesReturn(
      returnId: returnId,
      lines: [
        {'product_id': productId, 'qty': 1.0, 'price': 10.0, 'good': 1.0},
      ],
    );

    final customers = await helper.query('customers', where: 'id=?', whereArgs: [1]);
    final cashBoxes = await helper.query('cash_boxes', where: 'id=?', whereArgs: [1]);
    expect((customers.single['balance'] as num).toDouble(), 10);
    expect((cashBoxes.single['balance'] as num).toDouble(), 0);
    await expectJournalBalanced('SALES_RETURN', returnId);
  });

  test('inventory count posts simultaneous increases and shortages separately',
      () async {
    final db = await helper.database;
    final increaseProductId = await createProduct(cost: 4);
    final shortageProductId = await createProduct(cost: 3);
    await db.insert('inventory', {
      'product_id': increaseProductId,
      'warehouse_id': 1,
      'qty': 5,
    });
    await db.insert('inventory', {
      'product_id': shortageProductId,
      'warehouse_id': 1,
      'qty': 8,
    });
    final documentId = await db.insert('inventory_documents', {
      'document_no': 'TEST-COUNT-MIXED-1',
      'inventory_date': today(),
      'warehouse_id': 1,
      'inventory_type': 'فعلي',
      'status': 'معتمد',
    });
    await db.insert('inventory_items', {
      'document_id': documentId,
      'product_id': increaseProductId,
      'book_qty': 5,
      'count_qty': 7,
    });
    await db.insert('inventory_items', {
      'document_id': documentId,
      'product_id': shortageProductId,
      'book_qty': 8,
      'count_qty': 6,
    });

    await helper.postInventoryCount(documentId: documentId);

    final increaseStock = await helper.query(
      'inventory',
      where: 'product_id=? AND warehouse_id=?',
      whereArgs: [increaseProductId, 1],
    );
    final shortageStock = await helper.query(
      'inventory',
      where: 'product_id=? AND warehouse_id=?',
      whereArgs: [shortageProductId, 1],
    );
    final journal = await helper.query(
      'accounting_entries',
      where: 'source_type=? AND source_id=?',
      whereArgs: ['COUNT', documentId],
    );
    final journalLines = await helper.query(
      'accounting_entry_lines',
      where: 'entry_id=?',
      whereArgs: [journal.single['id']],
    );

    expect((increaseStock.single['qty'] as num).toDouble(), 7);
    expect((shortageStock.single['qty'] as num).toDouble(), 6);
    expect(journalLines, hasLength(4));
    await expectJournalBalanced('COUNT', documentId);
  });

  test('inventory count rejects negative counted quantities atomically',
      () async {
    final db = await helper.database;
    final productId = await createProduct();
    await db.insert('inventory', {
      'product_id': productId,
      'warehouse_id': 1,
      'qty': 5,
    });
    final documentId = await db.insert('inventory_documents', {
      'document_no': 'TEST-COUNT-NEGATIVE-1',
      'inventory_date': today(),
      'warehouse_id': 1,
      'inventory_type': 'فعلي',
      'status': 'معتمد',
    });
    await db.insert('inventory_items', {
      'document_id': documentId,
      'product_id': productId,
      'book_qty': 5,
      'count_qty': -1,
    });

    await expectLater(
      helper.postInventoryCount(documentId: documentId),
      throwsA(isA<StateError>()),
    );
    final stock = await helper.query(
      'inventory',
      where: 'product_id=? AND warehouse_id=?',
      whereArgs: [productId, 1],
    );
    final document = await helper.query(
      'inventory_documents',
      where: 'id=?',
      whereArgs: [documentId],
    );
    expect((stock.single['qty'] as num).toDouble(), 5);
    expect(document.single['status'], 'معتمد');
    expect(
      await helper.query(
        'accounting_entries',
        where: 'source_type=? AND source_id=?',
        whereArgs: ['COUNT', documentId],
      ),
      isEmpty,
    );
  });

}
