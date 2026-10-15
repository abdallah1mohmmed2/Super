import 'package:flutter/widgets.dart';
import '../data_screen.dart';

/// Dedicated route for the transfers module; fields and table behavior are configured centrally.
class WarehouseTransfersScreen extends StatelessWidget {
  const WarehouseTransfersScreen({super.key});
  @override Widget build(BuildContext context) => const DataScreen(screenKey: 'transfers');
}
