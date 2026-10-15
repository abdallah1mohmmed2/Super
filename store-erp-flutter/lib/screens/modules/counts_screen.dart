import 'package:flutter/widgets.dart';
import '../data_screen.dart';

/// Dedicated route for the counts module; fields and table behavior are configured centrally.
class PhysicalCountScreen extends StatelessWidget {
  const PhysicalCountScreen({super.key});
  @override Widget build(BuildContext context) => const DataScreen(screenKey: 'counts');
}
