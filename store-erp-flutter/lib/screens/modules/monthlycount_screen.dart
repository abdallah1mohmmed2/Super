import 'package:flutter/widgets.dart';
import 'inventory_count_screen.dart';

class MonthlyCountScreen extends StatelessWidget {
  const MonthlyCountScreen({super.key});
  @override
  Widget build(BuildContext context) => const InventoryCountScreen(countType: 'monthlycount');
}
