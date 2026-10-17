import 'package:flutter/widgets.dart';
import 'inventory_count_screen.dart';

class PhysicalCountScreen extends StatelessWidget {
  const PhysicalCountScreen({super.key});
  @override
  Widget build(BuildContext context) => const InventoryCountScreen(countType: 'counts');
}
