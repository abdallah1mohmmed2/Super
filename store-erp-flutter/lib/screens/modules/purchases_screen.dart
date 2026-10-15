import 'package:flutter/widgets.dart';
import '../data_screen.dart';

/// Dedicated route for the purchases module; fields and table behavior are configured centrally.
class PurchasesScreen extends StatelessWidget {
  const PurchasesScreen({super.key});
  @override Widget build(BuildContext context) => const DataScreen(screenKey: 'purchases');
}
