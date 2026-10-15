import 'package:flutter/widgets.dart';
import '../data_screen.dart';

/// Dedicated route for the inventory module; fields and table behavior are configured centrally.
class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});
  @override Widget build(BuildContext context) => const DataScreen(screenKey: 'inventory');
}
