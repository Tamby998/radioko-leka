// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:radiokoleka/main.dart';

void main() {
  testWidgets('affiche l accueil Radioko Leka', (tester) async {
    await tester.pumpWidget(const RadiokoLekaApp());

    expect(find.text('RADIOKO LEKA'), findsOneWidget);
    expect(find.text('Radios populaires'), findsOneWidget);
    expect(find.text('Viva Radio'), findsOneWidget);
  });
}
