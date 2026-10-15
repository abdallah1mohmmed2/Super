import 'package:flutter/widgets.dart';
import '../data_screen.dart';

/// Dedicated route for the damage module; fields and table behavior are configured centrally.
class DamageDocumentsScreen extends StatelessWidget {
  const DamageDocumentsScreen({super.key});
  @override Widget build(BuildContext context) => const DataScreen(screenKey: 'damage');
}
