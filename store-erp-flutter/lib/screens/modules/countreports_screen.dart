import 'package:flutter/widgets.dart';
import '../data_screen.dart';

/// Dedicated route for the countreports module; fields and table behavior are configured centrally.
class CountReportsScreen extends StatelessWidget {
  const CountReportsScreen({super.key});
  @override Widget build(BuildContext context) => const DataScreen(screenKey: 'countreports');
}
