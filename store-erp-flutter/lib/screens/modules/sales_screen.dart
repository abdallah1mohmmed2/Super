import 'package:flutter/widgets.dart';
import '../data_screen.dart';

/// Dedicated route for the sales module; fields and table behavior are configured centrally.
class SalesScreen extends StatelessWidget {
  const SalesScreen({super.key});
  @override Widget build(BuildContext context) => const DataScreen(screenKey: 'sales');
}
