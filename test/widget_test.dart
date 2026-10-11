// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_antideg/main.dart';

void main() {
  testWidgets('home screen shows categories and scheduled tasks', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const AntiProcrastinationApp());
    await tester.pumpAndSettle();

    expect(find.text('Мой ритм'), findsOneWidget);
    expect(find.text('Похудение'), findsWidgets);
    expect(find.text('Пробежка 20 минут'), findsOneWidget);

    await tester.tap(find.text('Неделя'));
    await tester.pumpAndSettle();

    expect(find.text('Шаблон недели'), findsOneWidget);
    expect(find.text('Понедельник'), findsOneWidget);
  });
}
