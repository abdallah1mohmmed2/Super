import 'package:flutter/widgets.dart';
import '../data_screen.dart';

/// Dedicated route for the cashboxes module; fields and table behavior are configured centrally.
class CashBoxesScreen extends StatelessWidget {
  const CashBoxesScreen({super.key});
  @override Widget build(BuildContext context) => const DataScreen(screenKey: 'cashboxes');
}
