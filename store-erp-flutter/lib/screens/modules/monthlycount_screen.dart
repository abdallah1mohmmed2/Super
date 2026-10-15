import 'package:flutter/widgets.dart';
import '../data_screen.dart';

/// Dedicated route for the monthlycount module; fields and table behavior are configured centrally.
class MonthlyCountScreen extends StatelessWidget {
  const MonthlyCountScreen({super.key});
  @override Widget build(BuildContext context) => const DataScreen(screenKey: 'monthlycount');
}
