import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nemanga/models/reader_models.dart';
import 'package:nemanga/screens/manga_file_explorer_screen.dart';

void main() {
  const channel = MethodChannel('com.nemanga.reader/compressor');
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory downloads;
  bool granted = false;
  int requests = 0;
  setUp(() {
    downloads = Directory.systemTemp.createTempSync('explorer_downloads');
    granted = false;
    requests = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'hasAllFilesAccess': return granted;
        case 'requestAllFilesAccess': requests++; return true;
        case 'getDownloadsDirectory': return downloads.path;
      }
      return null;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    downloads.deleteSync(recursive: true);
  });
  Future<void> open(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(home: MangaFileExplorerScreen(
        settings: ReaderSettings(),
      )));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
  }
  testWidgets('first frame and denied permission do not open sandbox', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await open(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Доступ к хранилищу ограничен'), findsOneWidget);
    expect(find.textContaining('app_flutter'), findsNothing);
    await tester.tap(find.text('Разрешить доступ ко всем файлам'));
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
    expect(requests, 1);
    expect(find.text('Доступ к хранилищу ограничен'), findsOneWidget);
  });
  testWidgets('granted access starts in system Downloads and button returns there', (tester) async {
    granted = true;
    Directory('${downloads.path}/ChapterFolder').createSync();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await open(tester);
    expect(find.text('ChapterFolder'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('ChapterFolder'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Перейти в Загрузки'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('ChapterFolder'), findsOneWidget);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('return from settings loads Downloads without prompting again', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await open(tester);
    granted = true;
    Directory('${downloads.path}/ReturnedFolder').createSync();
    await tester.runAsync(() async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('ReturnedFolder'), findsOneWidget);
    expect(find.text('Доступ к хранилищу ограничен'), findsNothing);
    expect(requests, 0);
    debugDefaultTargetPlatformOverride = null;
  });
}
