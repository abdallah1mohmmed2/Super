import 'package:flutter/widgets.dart';
import '../data_screen.dart';

/// Dedicated route for the countdocs module; fields and table behavior are configured centrally.
class InventoryDocumentsScreen extends StatelessWidget {
  const InventoryDocumentsScreen({super.key});
  @override Widget build(BuildContext context) => const DataScreen(screenKey: 'countdocs');
}
