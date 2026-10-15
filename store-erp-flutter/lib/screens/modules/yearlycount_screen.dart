import 'package:flutter/widgets.dart';
import '../data_screen.dart';

/// Dedicated route for the yearlycount module; fields and table behavior are configured centrally.
class YearlyCountScreen extends StatelessWidget {
  const YearlyCountScreen({super.key});
  @override Widget build(BuildContext context) => const DataScreen(screenKey: 'yearlycount');
}
