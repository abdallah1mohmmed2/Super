import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_theme.dart';
import '../providers/app_provider.dart';
import '../widgets/common_widgets.dart';

class DashboardScreen extends StatefulWidget {
  final ValueChanged<String> onOpen;
  const DashboardScreen({super.key, required this.onOpen});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<_DashboardData> _future;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _future = _load(context.read<AppProvider>());
      _initialized = true;
    }
  }

  Future<void> _refreshDashboard() async {
    final provider = context.read<AppProvider>();
    await provider.refresh();
    if (!mounted) return;
    setState(() => _future = _load(provider));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DashboardData>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data ?? _DashboardData.empty();
        return ListView(padding: const EdgeInsets.all(20), children: [
          Row(children: [
            const Expanded(child: Text('لوحة التحكم', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold))),
            OutlinedButton.icon(
              onPressed: _refreshDashboard,
              icon: const Icon(Icons.refresh),
              label: const Text('تحديث المؤشرات'),
            ),
          ]),
          const SizedBox(height: 6),
          Text('نظرة عامة على أداء المتجر والمخزون', style: TextStyle(color: Colors.blueGrey.shade600)),
          const SizedBox(height: 18),
          if (snapshot.connectionState == ConnectionState.waiting) const LinearProgressIndicator(),
          GridView.count(crossAxisCount: MediaQuery.sizeOf(context).width > 1300 ? 4 : MediaQuery.sizeOf(context).width > 800 ? 3 : 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 2.1, children: [
            StatCard(title: 'مبيعات اليوم', value: _money(data.todaySales), icon: Icons.point_of_sale, color: AppTheme.emerald),
            StatCard(title: 'المشتريات', value: _money(data.purchaseTotal), icon: Icons.shopping_cart_outlined, color: AppTheme.sky),
            StatCard(title: 'قيمة المخزون التقديرية', value: _money(data.stockValue), icon: Icons.inventory_2_outlined, color: Colors.deepPurple),
            StatCard(title: 'ذمم العملاء', value: _money(data.customerBalances), icon: Icons.people_alt_outlined, color: Colors.orange),
            StatCard(title: 'اعتمادات معلقة', value: data.pendingApprovals.toString(), icon: Icons.fact_check_outlined, color: Colors.deepOrange),
            StatCard(title: 'دفعات منتهية', value: data.expiredBatchCount.toString(), icon: Icons.event_busy_outlined, color: Colors.redAccent),
          ]),
          const SizedBox(height: 14),
          GridView.count(crossAxisCount: MediaQuery.sizeOf(context).width > 1000 ? 3 : 1, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisSpacing: 14, mainAxisSpacing: 14, childAspectRatio: 1.8, children: [
            _dashboardCard(context, 'فواتير المبيعات', Icons.point_of_sale, () => widget.onOpen('sales'), '${data.salesCount} فاتورة'),
            _dashboardCard(context, 'فواتير المشتريات', Icons.shopping_cart, () => widget.onOpen('purchases'), '${data.purchaseCount} فاتورة'),
            _dashboardCard(context, 'الأصناف', Icons.category, () => widget.onOpen('products'), '${data.productCount} صنف'),
            _dashboardCard(context, 'العملاء', Icons.people, () => widget.onOpen('customers'), '${data.customerCount} عميل'),
            _dashboardCard(context, 'تنبيهات قرب النفاد', Icons.warning_amber, () => widget.onOpen('inventory'), '${data.lowStockCount} صنف عند/دون حد إعادة الطلب'),
            _dashboardCard(context, 'اعتمادات المدير', Icons.verified_user_outlined, () => widget.onOpen('approvals'), '${data.pendingApprovals} طلب معلق'),
            _dashboardCard(context, 'تنبيهات انتهاء الدفعات', Icons.event_busy_outlined, () => widget.onOpen('inventory'), '${data.expiredBatchCount} دفعة منتهية'),
            _dashboardCard(context, 'الجرد والمستندات', Icons.fact_check, () => widget.onOpen('countdocs'), 'فتح مستندات الجرد'),
          ]),
          const SizedBox(height: 18),
          _indicatorTable('الأقسام الأكثر مبيعًا', data.topCategories, 'القسم'),
          _indicatorTable('الأقسام الأقل مبيعًا', data.bottomCategories, 'القسم'),
          _indicatorTable('المنتجات الأكثر مبيعًا', data.topProducts, 'الصنف'),
          _indicatorTable('المنتجات الأقل مبيعًا', data.bottomProducts, 'الصنف'),
          _indicatorTable('تنبيهات قرب النفاد', data.lowStockAlerts, 'الصنف'),
          _indicatorTable('تنبيهات قرب الانتهاء', data.nearExpiryAlerts, 'الصنف'),
          if (snapshot.hasError) Padding(padding: const EdgeInsets.only(top: 12), child: Text('تعذر تحديث بعض المؤشرات: ${snapshot.error}', style: const TextStyle(color: Colors.red))),
        ]);
      },
    );
  }

  Future<_DashboardData> _load(AppProvider provider) async {
    final db = provider.db;
    final sales = await db.query('sales_header');
    final purchases = await db.query('purchases_header');
    final inventory = await db.query('inventory');
    final products = await db.query('products');
    final customers = await db.query('customers');
    final reorder = await db.query('reorder_levels');
    final batches = await db.query('product_batches');
    final warehouses = await db.query('warehouses');
    final salesLines = await db.query('sales_lines');
    final categories = await db.query('categories');
    final approvals = await db.query('approval_requests', where: 'status=?', whereArgs: ['معلق']);
    final today = DateTime.now().toIso8601String().substring(0, 10);
    double sum(List<Map<String,Object?>> rows, String field) => rows.fold<double>(0, (total, row) => total + ((row[field] as num?)?.toDouble() ?? 0));
    double qtyFor(Object? productId, Object? warehouseId) {
      final rows = inventory.where((r) => r['product_id'] == productId && r['warehouse_id'] == warehouseId);
      return rows.isEmpty ? 0 : ((rows.first['qty'] as num?)?.toDouble() ?? 0);
    }
    final lowStockCount = reorder.where((r) => qtyFor(r['product_id'], r['warehouse_id']) <= ((r['minimum'] as num?)?.toDouble() ?? 0)).length;
    final expiredBatchCount = batches.where((r) {
      final qty = (r['qty'] as num?)?.toDouble() ?? 0;
      final expiry = DateTime.tryParse((r['expiry_date'] ?? '').toString());
      return qty > 0 && expiry != null && expiry.isBefore(DateTime.now());
    }).length;
    final postedSaleIds = sales.where((row) => row['status'] == 'مرحل')
        .map((row) => (row['id'] as num?)?.toInt()).whereType<int>().toSet();
    final productQty = <int, double>{};
    final categoryQty = <int, double>{};
    final productById = <int, Map<String, Object?>>{
      for (final product in products)
        if (product['id'] is num) (product['id'] as num).toInt(): product,
    };
    final categoryById = <int, Map<String, Object?>>{
      for (final category in categories)
        if (category['id'] is num) (category['id'] as num).toInt(): category,
    };
    for (final line in salesLines) {
      final saleId = (line['sales_id'] as num?)?.toInt();
      final productId = (line['product_id'] as num?)?.toInt();
      if (saleId == null || productId == null || !postedSaleIds.contains(saleId)) continue;
      final qty = ((line['qty'] as num?)?.toDouble() ?? 0) *
          ((line['factor'] as num?)?.toDouble() ?? 1);
      productQty[productId] = (productQty[productId] ?? 0) + qty;
      final categoryId = (productById[productId]?['category_id'] as num?)?.toInt();
      if (categoryId != null) categoryQty[categoryId] = (categoryQty[categoryId] ?? 0) + qty;
    }
    List<Map<String, Object?>> rankAll(
      Iterable<Map<String, Object?>> source,
      Map<int, double> quantities,
    ) {
      final rows = source.where((row) => row['id'] is num).map((row) {
        final id = (row['id'] as num).toInt();
        return <String, Object?>{
          'name': row['name'] ?? '—',
          'qty': quantities[id] ?? 0.0,
        };
      }).toList();
      rows.sort((a, b) => ((b['qty'] as num).toDouble()).compareTo((a['qty'] as num).toDouble()));
      return rows;
    }
    // Include zero-sales items so the "least sold" indicators are meaningful.
    final productsRanked = rankAll(products, productQty);
    final categoriesRanked = rankAll(categories, categoryQty);
    final lowStockAlerts = reorder.where((row) {
      final qty = qtyFor(row['product_id'], row['warehouse_id']);
      return qty <= ((row['minimum'] as num?)?.toDouble() ?? 0);
    }).map((row) {
      final product = productById[(row['product_id'] as num?)?.toInt()];
      final warehouse = warehouses.where((w) => w['id'] == row['warehouse_id']);
      return <String, Object?>{
        'name': product?['name'] ?? 'صنف غير معروف',
        'warehouse': warehouse.isEmpty ? '—' : (warehouse.first['name'] ?? '—'),
        'qty': qtyFor(row['product_id'], row['warehouse_id']),
        'minimum': (row['minimum'] as num?)?.toDouble() ?? 0,
      };
    }).take(10).toList();
    final todayDate = DateTime.now();
    final nearExpiryAlerts = batches.where((row) {
      final qty = (row['qty'] as num?)?.toDouble() ?? 0;
      final expiry = DateTime.tryParse((row['expiry_date'] ?? '').toString());
      if (qty <= 0 || expiry == null) return false;
      final days = expiry.difference(DateTime(todayDate.year, todayDate.month, todayDate.day)).inDays;
      return days >= 0 && days <= 30;
    }).toList()
      ..sort((a, b) => (DateTime.tryParse((a['expiry_date'] ?? '').toString()) ?? DateTime(9999))
          .compareTo(DateTime.tryParse((b['expiry_date'] ?? '').toString()) ?? DateTime(9999)));
    final nearExpiryRows = nearExpiryAlerts.take(10).map((row) {
      final product = productById[(row['product_id'] as num?)?.toInt()];
      final warehouse = warehouses.where((w) => w['id'] == row['warehouse_id']);
      return <String, Object?>{
        'name': product?['name'] ?? 'صنف غير معروف',
        'warehouse': warehouse.isEmpty ? '—' : (warehouse.first['name'] ?? '—'),
        'qty': (row['qty'] as num?)?.toDouble() ?? 0,
        'expiry': (row['expiry_date'] ?? '—').toString(),
      };
    }).toList();
    final bottomProducts = productsRanked.reversed.take(5).toList();
    final bottomCategories = categoriesRanked.reversed.take(5).toList();
    return _DashboardData(
      todaySales: sum(sales.where((r) => (r['invoice_date']?.toString() ?? '').startsWith(today) && r['status'] == 'مرحل').toList(), 'net'),
      purchaseTotal: sum(purchases.where((r) => r['status'] == 'مرحل').toList(), 'net'),
      stockValue: inventory.fold<double>(0, (total, row) { final product = products.where((p) => p['id'] == row['product_id']); final cost = product.isEmpty ? 0.0 : ((product.first['cost_price'] as num?)?.toDouble() ?? 0); return total + cost * ((row['qty'] as num?)?.toDouble() ?? 0); }),
      customerBalances: sum(customers, 'balance'), salesCount: sales.where((r) => r['status'] == 'مرحل').length, purchaseCount: purchases.where((r) => r['status'] == 'مرحل').length,
      productCount: products.length, customerCount: customers.length,
      lowStockCount: lowStockCount, pendingApprovals: approvals.length, expiredBatchCount: expiredBatchCount,
      topProducts: productsRanked.take(5).toList(),
      bottomProducts: bottomProducts,
      topCategories: categoriesRanked.take(5).toList(),
      bottomCategories: bottomCategories,
      lowStockAlerts: lowStockAlerts,
      nearExpiryAlerts: nearExpiryRows,
    );
  }
  String _money(double value) => value.toStringAsFixed(2);

  Widget _indicatorTable(String title, List<Map<String, Object?>> rows, String firstColumn) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            const Text('لا توجد بيانات مطابقة حاليًا', style: TextStyle(color: Colors.blueGrey))
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  DataColumn(label: Text(firstColumn)),
                  if (rows.first.containsKey('warehouse')) const DataColumn(label: Text('المخزن')),
                  if (rows.first.containsKey('qty')) const DataColumn(label: Text('الكمية')),
                  if (rows.first.containsKey('minimum')) const DataColumn(label: Text('حد إعادة الطلب')),
                  if (rows.first.containsKey('expiry')) const DataColumn(label: Text('تاريخ الانتهاء')),
                ],
                rows: rows.map((row) => DataRow(cells: [
                  DataCell(Text((row['name'] ?? '—').toString())),
                  if (row.containsKey('warehouse')) DataCell(Text((row['warehouse'] ?? '—').toString())),
                  if (row.containsKey('qty')) DataCell(Text(((row['qty'] as num?)?.toDouble() ?? 0).toStringAsFixed(2))),
                  if (row.containsKey('minimum')) DataCell(Text(((row['minimum'] as num?)?.toDouble() ?? 0).toStringAsFixed(2))),
                  if (row.containsKey('expiry')) DataCell(Text((row['expiry'] ?? '—').toString())),
                ])).toList(),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _dashboardCard(BuildContext context, String title, IconData icon, VoidCallback onTap, String detail) => Card(child: InkWell(borderRadius: BorderRadius.circular(14), onTap: onTap, child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Icon(icon, color: AppTheme.emerald), const SizedBox(width: 10), Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)))]), const Divider(height: 28), Expanded(child: Center(child: Text(detail, style: const TextStyle(color: Colors.blueGrey, fontSize: 16)))), Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: onTap, child: const Text('عرض التفاصيل')))]))));
}

class _DashboardData {
  final double todaySales, purchaseTotal, stockValue, customerBalances;
  final int salesCount, purchaseCount, productCount, customerCount, lowStockCount, pendingApprovals, expiredBatchCount;
  final List<Map<String, Object?>> topProducts, bottomProducts, topCategories, bottomCategories, lowStockAlerts, nearExpiryAlerts;
  const _DashboardData({
    this.todaySales=0, this.purchaseTotal=0, this.stockValue=0, this.customerBalances=0,
    this.salesCount=0, this.purchaseCount=0, this.productCount=0, this.customerCount=0,
    this.lowStockCount=0, this.pendingApprovals=0, this.expiredBatchCount=0,
    this.topProducts=const [], this.bottomProducts=const [], this.topCategories=const [], this.bottomCategories=const [],
    this.lowStockAlerts=const [], this.nearExpiryAlerts=const [],
  });
  factory _DashboardData.empty() => const _DashboardData();
}
