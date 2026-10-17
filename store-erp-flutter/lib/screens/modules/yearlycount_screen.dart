import 'package:flutter/widgets.dart';
import 'inventory_count_screen.dart';

class YearlyCountScreen extends StatelessWidget {
  const YearlyCountScreen({super.key});
  @override
  Widget build(BuildContext context) => const InventoryCountScreen(countType: 'yearlycount');
}
