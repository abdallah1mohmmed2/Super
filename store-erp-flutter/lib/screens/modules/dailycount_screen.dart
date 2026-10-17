import 'package:flutter/widgets.dart';
import 'inventory_count_screen.dart';

class DailyCountScreen extends StatelessWidget {
  const DailyCountScreen({super.key});
  @override
  Widget build(BuildContext context) => const InventoryCountScreen(countType: 'dailycount');
}
