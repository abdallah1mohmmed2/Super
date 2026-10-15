import 'package:flutter/widgets.dart';
import 'sales_screen.dart';
import 'purchases_screen.dart';
import 'returns_screen.dart';
import 'inventory_screen.dart';
import 'transfers_screen.dart';
import 'damage_screen.dart';
import 'products_screen.dart';
import 'customers_screen.dart';
import 'suppliers_screen.dart';
import 'users_screen.dart';
import 'cashboxes_screen.dart';
import 'cashtransfers_screen.dart';
import 'countdocs_screen.dart';
import 'counts_screen.dart';
import 'dailycount_screen.dart';
import 'monthlycount_screen.dart';
import 'yearlycount_screen.dart';
import 'countreports_screen.dart';
import 'reports_screen.dart';
import 'backup_screen.dart';
import 'closing_screen.dart';

class ModuleScreen extends StatelessWidget {
  final String screenKey;
  const ModuleScreen({super.key, required this.screenKey});
  @override Widget build(BuildContext context) => switch (screenKey) {
    'sales' => const SalesScreen(), 'purchases' => const PurchasesScreen(),
    'returns' => const SalesReturnsScreen(), 'inventory' => const InventoryScreen(),
    'transfers' => const WarehouseTransfersScreen(), 'damage' => const DamageDocumentsScreen(),
    'products' => const ProductsScreen(), 'customers' => const CustomersScreen(),
    'suppliers' => const SuppliersScreen(), 'users' => const UsersScreen(),
    'cashboxes' => const CashBoxesScreen(), 'cashtransfers' => const CashTransfersScreen(),
    'countdocs' => const InventoryDocumentsScreen(), 'counts' => const PhysicalCountScreen(),
    'dailycount' => const DailyCountScreen(), 'monthlycount' => const MonthlyCountScreen(),
    'yearlycount' => const YearlyCountScreen(), 'countreports' => const CountReportsScreen(),
    'reports' => const ReportsScreen(), 'backup' => const BackupScreen(),
    'closing' => const DailyClosingScreen(), _ => const ProductsScreen(),
  };
}
