import 'package:flutter/widgets.dart';
import '../data_screen.dart';

/// Dedicated route for the dailycount module; fields and table behavior are configured centrally.
class DailyCountScreen extends StatelessWidget {
  const DailyCountScreen({super.key});
  @override Widget build(BuildContext context) => const DataScreen(screenKey: 'dailycount');
}
