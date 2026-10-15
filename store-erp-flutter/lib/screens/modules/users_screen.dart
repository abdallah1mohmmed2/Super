import 'package:flutter/widgets.dart';
import '../data_screen.dart';

/// Dedicated route for the users module; fields and table behavior are configured centrally.
class UsersScreen extends StatelessWidget {
  const UsersScreen({super.key});
  @override Widget build(BuildContext context) => const DataScreen(screenKey: 'users');
}
