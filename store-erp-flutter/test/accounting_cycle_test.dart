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

  Future<void> expectBalanced(String type, int sourceId) async {
    final entries = await helper.query(
      'accounting_entries',
      where: 'source_type=? AND source_id=?',
      whereArgs: [type, sourceId],
    );
    expect(entries, hasLength(1));
    final lines = await helper.query(
      'accounting_entry_lines',
      where: 'entry_id=?',
      whereArgs: [entries.single['id']],
    );
    final debit = lines.fold<double>(
      0,
      (sum, row) => sum + (row['debit'] as num).toDouble(),
    );
    final credit = lines.fold<double>(
      0,
      (sum, row) => sum + (row['credit'] as num).toDouble(),
    );
    expect((debit - credit).abs(), lessThan(0.005));
  }

  test('purchase -> sale -> return keeps stock, cash, supplier and journals consistent',
      () async {
    final db = await helper.database;
    final productId = await db.insert('products', {
      'name': 'صنف دورة متكاملة',
      'cost_price': 4,
      'sale_price': 10,
      'is_active': 1,
    });
    final supplierId = await db.insert('suppliers', {
      'name': 'مورد دورة متكاملة',
      'balance': 0,
      'is_active': 1,
    });

    final purchaseId = await db.insert('purchases_header', {
      'invoice_no': 'CYCLE-PURCHASE-1',
      'invoice_date': today(),
      'supplier_id': supplierId,
      'warehouse_id': 1,
      'cash_box_id': 1,
      'payment_method': 'على الرصيد',
      'net': 40,
      'paid': 0,
      'status': 'مسودة',
    });
    await db.insert('purchases_lines', {
      'purchase_id': purchaseId,
      'product_id': productId,
      'unit': 'قطعة',
      'factor': 1,
      'qty': 10,
      'cost': 4,
      'discount': 0,
      'tax': 0,
      'line_total': 40,
    });

    await helper.postPurchase(
      purchaseId: purchaseId,
      warehouseId: 1,
      cashBoxId: 1,
      supplierId: supplierId,
      net: 40,
      paid: 0,
      lines: [
        {'product_id': productId, 'qty': 10, 'factor': 1, 'cost': 4},
      ],
    );

    var stock = await helper.query(
      'inventory',
      where: 'product_id=? AND warehouse_id=?',
      whereArgs: [productId, 1],
    );
    var supplier = await helper.query(
      'suppliers',
      where: 'id=?',
      whereArgs: [supplierId],
    );
    expect((stock.single['qty'] as num).toDouble(), 10);
    expect((supplier.single['balance'] as num).toDouble(), 40);
    await expectBalanced('PURCHASE', purchaseId);

    final sessionId = await db.insert('cash_sessions', {
      'cash_box_id': 1,
      'session_no': 'CYCLE-SESSION-1',
      'opened_at': DateTime.now().toIso8601String(),
      'opening_balance': 0,
      'status': 'مفتوحة',
      'opened_by': 'test',
    });
    final saleId = await db.insert('sales_header', {
      'invoice_no': 'CYCLE-SALE-1',
      'invoice_date': today(),
      'warehouse_id': 1,
      'cash_box_id': 1,
      'cash_session_id': sessionId,
      'cashier': 'test',
      'payment_method': 'نقدي',
      'net': 30,
      'paid': 30,
      'status': 'مسودة',
    });
    await db.insert('sales_lines', {
      'sales_id': saleId,
      'product_id': productId,
      'unit': 'قطعة',
      'factor': 1,
      'qty': 3,
      'price': 10,
      'discount': 0,
      'tax': 0,
      'line_total': 30,
    });

    await helper.postSale(
      saleId: saleId,
      warehouseId: 1,
      cashBoxId: 1,
      lines: [
        {'product_id': productId, 'qty': 3, 'factor': 1},
      ],
      net: 30,
      paid: 30,
    );

    stock = await helper.query(
      'inventory',
      where: 'product_id=? AND warehouse_id=?',
      whereArgs: [productId, 1],
    );
    var cash = await helper.query('cash_boxes', where: 'id=?', whereArgs: [1]);
    expect((stock.single['qty'] as num).toDouble(), 7);
    expect((cash.single['balance'] as num).toDouble(), 30);
    await expectBalanced('SALE', saleId);

    final returnId = await db.insert('sales_returns', {
      'return_no': 'CYCLE-RETURN-1',
      'sales_id': saleId,
      'warehouse_id': 1,
      'return_date': today(),
      'total': 10,
      'status': 'مسودة',
      'reason': 'اختبار دورة متكاملة',
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
      'method': 'نقدي',
      'amount': 10,
    });

    await helper.postSalesReturn(
      returnId: returnId,
      lines: [
        {'product_id': productId, 'qty': 1, 'price': 10, 'good': 1},
      ],
    );

    stock = await helper.query(
      'inventory',
      where: 'product_id=? AND warehouse_id=?',
      whereArgs: [productId, 1],
    );
    cash = await helper.query('cash_boxes', where: 'id=?', whereArgs: [1]);
    final returned = await helper.query(
      'sales_returns',
      where: 'id=?',
      whereArgs: [returnId],
    );
    expect((stock.single['qty'] as num).toDouble(), 8);
    expect((cash.single['balance'] as num).toDouble(), 20);
    expect(returned.single['status'], 'مرحل');
    expect((supplier.single['balance'] as num).toDouble(), 40);
    await expectBalanced('SALES_RETURN', returnId);

    await expectLater(
      helper.postSalesReturn(
        returnId: returnId,
        lines: [
          {'product_id': productId, 'qty': 1, 'price': 10, 'good': 1},
        ],
      ),
      throwsA(isA<StateError>()),
    );
    stock = await helper.query(
      'inventory',
      where: 'product_id=? AND warehouse_id=?',
      whereArgs: [productId, 1],
    );
    cash = await helper.query('cash_boxes', where: 'id=?', whereArgs: [1]);
    expect((stock.single['qty'] as num).toDouble(), 8);
    expect((cash.single['balance'] as num).toDouble(), 20);
    expect(
      await helper.query(
        'accounting_entries',
        where: 'source_type=? AND source_id=?',
        whereArgs: ['SALES_RETURN', returnId],
      ),
      hasLength(1),
    );
  });

  test('failed sale with no open session leaves stock, cash and journal untouched',
      () async {
    final db = await helper.database;
    final productId = await db.insert('products', {
      'name': 'صنف اختبار فشل الجلسة',
      'cost_price': 2,
      'sale_price': 5,
      'is_active': 1,
    });
    await db.insert('inventory', {
      'product_id': productId,
      'warehouse_id': 1,
      'qty': 5,
    });
    final saleId = await db.insert('sales_header', {
      'invoice_no': 'CYCLE-FAIL-SALE-1',
      'invoice_date': today(),
      'warehouse_id': 1,
      'cash_box_id': 1,
      'net': 10,
      'paid': 10,
      'status': 'مسودة',
    });
    await db.insert('sales_lines', {
      'sales_id': saleId,
      'product_id': productId,
      'unit': 'قطعة',
      'factor': 1,
      'qty': 2,
      'price': 5,
      'discount': 0,
      'tax': 0,
      'line_total': 10,
    });

    await expectLater(
      helper.postSale(
        saleId: saleId,
        warehouseId: 1,
        cashBoxId: 1,
        lines: [
          {'product_id': productId, 'qty': 2, 'factor': 1},
        ],
        net: 10,
        paid: 10,
      ),
      throwsA(isA<StateError>()),
    );

    final stock = await helper.query(
      'inventory',
      where: 'product_id=? AND warehouse_id=?',
      whereArgs: [productId, 1],
    );
    final cash = await helper.query('cash_boxes', where: 'id=?', whereArgs: [1]);
    final sale = await helper.query(
      'sales_header',
      where: 'id=?',
      whereArgs: [saleId],
    );
    expect((stock.single['qty'] as num).toDouble(), 5);
    expect((cash.single['balance'] as num).toDouble(), 0);
    expect(sale.single['status'], 'مسودة');
    expect(
      await helper.query(
        'accounting_entries',
        where: 'source_type=? AND source_id=?',
        whereArgs: ['SALE', saleId],
      ),
      isEmpty,
    );
  });
}
