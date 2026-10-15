import 'package:flutter/widgets.dart';
import '../data_screen.dart';

/// Dedicated route for the products module; fields and table behavior are configured centrally.
class ProductsScreen extends StatelessWidget {
  const ProductsScreen({super.key});
  @override Widget build(BuildContext context) => const DataScreen(screenKey: 'products');
}
