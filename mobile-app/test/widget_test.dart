import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mentalhealthapp/app_shell.dart';

void main() {
  testWidgets('shows the auth landing screen', (WidgetTester tester) async {
    // Pump the AuthScreen directly to avoid async bootstrap (secure storage / network)
    await tester.pumpWidget(MaterialApp(
      home: AuthScreen(onAuthenticated: (() async {})),
    ));

    await tester.pumpAndSettle();

    expect(find.text('MindCare'), findsOneWidget);
    expect(find.text('Continue anonymously'), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);
  });
}
