import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nemanga/models/reader_models.dart';
import 'package:nemanga/screens/reader_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Валидный 200x100 PNG
  final validPngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAMgAAABkCAIAAABM5OhcAAABGklEQVR4nO3SwQ3AIBDAsNL9dz6WIEJC9gR5ZM3MB6f9twN4k7FIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIuEsUgYi4SxSBiLhLFIGIvEBlOUA8XCwqj8AAAAAElFTkSuQmCC',
  );

  testWidgets('volume navigation visits both halves of first and last spreads', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final temp = Directory.systemTemp.createTempSync('reader_nav_');
    addTearDown(() => temp.deleteSync(recursive: true));

    final paths = <String>[];
    for (var i = 0; i < 2; i++) {
      final file = File('${temp.path}/$i.png');
      file.writeAsBytesSync(validPngBytes);
      paths.add(file.path);
    }

    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(
        title: 'Navigation test',
        archivePath: '${temp.path}/test.cbz',
        pagePaths: paths,
        settings: const ReaderSettings(
          mode: ReaderMode.horizontalLtr,
          hapticFeedback: false,
          splitDoublePages: true,
        ),
      ),
    ));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final controller = tester.widget<PageView>(find.byType(PageView)).controller!;
    expect(controller.page, 0);

    // Навигация кнопкой громкости вниз: переход на следующую виртуальную страницу
    await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.page, 1);

    // Назад кнопкой громкости вверх
    await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeUp);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.page, 0);

    // Проходим все 4 виртуальные страницы (2 разворота * 2 половины = 4)
    for (var i = 1; i <= 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.page, i);
    }

    // Дальше последней страницы не уходит
    await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.page, 3);

    // Очищаем виджет и ждём завершения таймеров скрытия баров
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
  });
}
