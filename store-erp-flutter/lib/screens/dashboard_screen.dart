import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_theme.dart';
import '../providers/app_provider.dart';
import '../widgets/common_widgets.dart';

class DashboardScreen extends StatelessWidget {
  final ValueChanged<String> onOpen;
  const DashboardScreen({super.key, required this.onOpen});

  @override Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    return FutureBuilder<_DashboardData>(
      future: _load(provider),
      builder: (context, snapshot) {
        final data = snapshot.data ?? _DashboardData.empty();
        return ListView(padding: const EdgeInsets.all(20), children: [
          const Text('لوحة التحكم', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('نظرة عامة على أداء المتجر والمخزون', style: TextStyle(color: Colors.blueGrey.shade600)),
          const SizedBox(height: 18),
          if (snapshot.connectionState == ConnectionState.waiting) const LinearProgressIndicator(),
          GridView.count(crossAxisCount: MediaQuery.sizeOf(context).width > 1300 ? 4 : MediaQuery.sizeOf(context).width > 800 ? 3 : 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 2.1, children: [
            StatCard(title: 'مبيعات اليوم', value: _money(data.todaySales), icon: Icons.point_of_sale, color: AppTheme.emerald),
            StatCard(title: 'المشتريات', value: _money(data.purchaseTotal), icon: Icons.shopping_cart_outlined, color: AppTheme.sky),
            StatCard(title: 'قيمة المخزون التقديرية', value: _money(data.stockValue), icon: Icons.inventory_2_outlined, color: Colors.deepPurple),
            StatCard(title: 'ذمم العملاء', value: _money(data.customerBalances), icon: Icons.people_alt_outlined, color: Colors.orange),
          ]),
          const SizedBox(height: 14),
          GridView.count(crossAxisCount: MediaQuery.sizeOf(context).width > 1000 ? 3 : 1, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisSpacing: 14, mainAxisSpacing: 14, childAspectRatio: 1.8, children: [
            _dashboardCard(context, 'فواتير المبيعات', Icons.point_of_sale, () => onOpen('sales'), '${data.salesCount} فاتورة'),
            _dashboardCard(context, 'فواتير المشتريات', Icons.shopping_cart, () => onOpen('purchases'), '${data.purchaseCount} فاتورة'),
            _dashboardCard(context, 'الأصناف', Icons.category, () => onOpen('products'), '${data.productCount} صنف'),
            _dashboardCard(context, 'العملاء', Icons.people, () => onOpen('customers'), '${data.customerCount} عميل'),
            _dashboardCard(context, 'تنبيهات قرب النفاد', Icons.warning_amber, () => onOpen('inventory'), '${data.lowStockCount} صنف رصيده صفر أو أقل'),
            _dashboardCard(context, 'الجرد والمستندات', Icons.fact_check, () => onOpen('countdocs'), 'فتح مستندات الجرد'),
          ]),
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
    final today = DateTime.now().toIso8601String().substring(0, 10);
    double sum(List<Map<String,Object?>> rows, String field) => rows.fold<double>(0, (total, row) => total + ((row[field] as num?)?.toDouble() ?? 0));
    return _DashboardData(
      todaySales: sum(sales.where((r) => (r['invoice_date']?.toString() ?? '').startsWith(today) && r['status'] == 'مرحل').toList(), 'net'),
      purchaseTotal: sum(purchases.where((r) => r['status'] == 'مرحل').toList(), 'net'),
      stockValue: inventory.fold<double>(0, (total, row) { final product = products.where((p) => p['id'] == row['product_id']); final cost = product.isEmpty ? 0.0 : ((product.first['cost_price'] as num?)?.toDouble() ?? 0); return total + cost * ((row['qty'] as num?)?.toDouble() ?? 0); }),
      customerBalances: sum(customers, 'balance'), salesCount: sales.length, purchaseCount: purchases.length,
      productCount: products.length, customerCount: customers.length,
      lowStockCount: inventory.where((r) => ((r['qty'] as num?)?.toDouble() ?? 0) <= 0).length,
    );
  }
  String _money(double value) => value.toStringAsFixed(2);
  Widget _dashboardCard(BuildContext context, String title, IconData icon, VoidCallback onTap, String detail) => Card(child: InkWell(borderRadius: BorderRadius.circular(14), onTap: onTap, child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Icon(icon, color: AppTheme.emerald), const SizedBox(width: 10), Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)))]), const Divider(height: 28), Expanded(child: Center(child: Text(detail, style: const TextStyle(color: Colors.blueGrey, fontSize: 16)))), Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: onTap, child: const Text('عرض التفاصيل')))]))));
}

class _DashboardData {
  final double todaySales, purchaseTotal, stockValue, customerBalances;
  final int salesCount, purchaseCount, productCount, customerCount, lowStockCount;
  const _DashboardData({this.todaySales=0,this.purchaseTotal=0,this.stockValue=0,this.customerBalances=0,this.salesCount=0,this.purchaseCount=0,this.productCount=0,this.customerCount=0,this.lowStockCount=0});
  factory _DashboardData.empty() => const _DashboardData();
}
