import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store_erp_flutter/main.dart';

void main() {
  testWidgets('Store ERP app displays the login screen', (tester) async {
    await tester.pumpWidget(const StoreErpApp());

    expect(find.text('نظام إدارة المتجر والمخزون'), findsOneWidget);
    expect(find.text('اسم المستخدم'), findsOneWidget);
    expect(find.text('كلمة المرور'), findsOneWidget);
    expect(find.text('دخول'), findsOneWidget);
  });

  testWidgets('Login validates required fields and toggles password visibility', (tester) async {
    await tester.pumpWidget(const StoreErpApp());

    await tester.enterText(find.byType(TextFormField).at(0), '');
    await tester.enterText(find.byType(TextFormField).at(1), '');
    await tester.tap(find.text('دخول'));
    await tester.pumpAndSettle();

    expect(find.text('أدخل اسم المستخدم'), findsOneWidget);
    expect(find.text('أدخل كلمة المرور'), findsOneWidget);

    expect(find.byIcon(Icons.visibility), findsOneWidget);
    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.visibility_off), findsOneWidget);
  });
}
