import 'package:flutter/widgets.dart';
import '../data_screen.dart';

/// Dedicated route for the cashtransfers module; fields and table behavior are configured centrally.
class CashTransfersScreen extends StatelessWidget {
  const CashTransfersScreen({super.key});
  @override Widget build(BuildContext context) => const DataScreen(screenKey: 'cashtransfers');
}
