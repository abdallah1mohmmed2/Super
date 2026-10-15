import 'package:flutter/widgets.dart';
import '../data_screen.dart';

/// Dedicated route for the customers module; fields and table behavior are configured centrally.
class CustomersScreen extends StatelessWidget {
  const CustomersScreen({super.key});
  @override Widget build(BuildContext context) => const DataScreen(screenKey: 'customers');
}
