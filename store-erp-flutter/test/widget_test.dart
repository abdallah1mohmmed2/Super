import 'package:flutter_test/flutter_test.dart';
import 'package:store_erp_flutter/main.dart';

void main() {
  testWidgets('Store ERP app displays the login screen', (tester) async {
    await tester.pumpWidget(const StoreErpApp());

    expect(find.text('نظام إدارة المتجر والمخزون'), findsOneWidget);
    expect(find.text('اسم المستخدم'), findsOneWidget);
    expect(find.text('كلمة المرور'), findsOneWidget);
  });
}
