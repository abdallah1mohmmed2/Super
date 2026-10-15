import 'package:flutter/widgets.dart';
import '../data_screen.dart';

/// Dedicated route for the returns module; fields and table behavior are configured centrally.
class SalesReturnsScreen extends StatelessWidget {
  const SalesReturnsScreen({super.key});
  @override Widget build(BuildContext context) => const DataScreen(screenKey: 'returns');
}
