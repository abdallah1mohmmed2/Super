import 'package:flutter/widgets.dart';
import '../data_screen.dart';

/// Dedicated route for the backup module; fields and table behavior are configured centrally.
class BackupScreen extends StatelessWidget {
  const BackupScreen({super.key});
  @override Widget build(BuildContext context) => const DataScreen(screenKey: 'backup');
}
