import 'package:flutter_test/flutter_test.dart';
import 'package:nemanga/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const NeMangaApp());
    expect(find.text('NeManga'), findsOneWidget);
    expect(find.text('Открыть архив(ы) манги'), findsOneWidget);
  });
}
