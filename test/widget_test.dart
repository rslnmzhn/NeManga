import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nemanga/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const NeMangaApp());
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('NeManga'), findsAtLeastNWidgets(1));
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
  });
}
