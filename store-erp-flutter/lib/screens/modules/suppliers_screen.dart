import 'package:flutter/widgets.dart';
import '../data_screen.dart';

/// Dedicated route for the suppliers module; fields and table behavior are configured centrally.
class SuppliersScreen extends StatelessWidget {
  const SuppliersScreen({super.key});
  @override Widget build(BuildContext context) => const DataScreen(screenKey: 'suppliers');
}
