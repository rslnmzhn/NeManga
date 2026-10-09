import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'compressor_service.dart';

class AppUpdateInfo {
  final String version;
  final String tag;
  final String releaseNotes;
  final String downloadUrl;
  final String fileName;
  final int fileSize;

  const AppUpdateInfo({
    required this.version,
    required this.tag,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.fileName,
    required this.fileSize,
  });
}

class UpdateService {
  static const MethodChannel _channel = MethodChannel('com.nemanga.reader/updater');
  static String _cachedCurrentVersion = '0.0.5';
  static String get currentVersion => _cachedCurrentVersion;
  static const String repoOwner = 'rslnmzhn';
  static const String repoName = 'NeManga';

  /// Получить актуальную версию установленного приложения из PackageManager
  static Future<String> getCurrentVersion() async {
    try {
      if (Platform.isAndroid) {
        final version = await _channel.invokeMethod<String>('getAppVersion');
        if (version != null && version.trim().isNotEmpty) {
          final clean = version.split('+').first.trim();
          _cachedCurrentVersion = clean;
          return clean;
        }
      }
    } catch (_) {}
    return _cachedCurrentVersion;
  }

  /// Сравнение версий: возвращает true, если candidate новее current
  static bool isNewerVersion(String current, String candidate) {
    // Очищаем от префиксов v и суффиксов
    final cleanCurrent = current.replaceFirst(RegExp(r'^v'), '').trim();
    final cleanCandidate = candidate.replaceFirst(RegExp(r'^v'), '').trim();

    if (cleanCurrent == cleanCandidate) return false;

    int parseVersionScore(String v) {
      final parts = v.split(RegExp(r'[\._]'));
      int major = 0;
      int minor = 0;
      int patch = 0;
      int fix = 0;

      for (int i = 0; i < parts.length; i++) {
        final part = parts[i];
        if (part.startsWith('fix')) {
          fix = int.tryParse(part.substring(3)) ?? 0;
        } else if (i == 0) {
          major = int.tryParse(part) ?? 0;
        } else if (i == 1) {
          minor = int.tryParse(part) ?? 0;
        } else if (i == 2) {
          patch = int.tryParse(part) ?? 0;
        }
      }

      return major * 1000000000 + minor * 1000000 + patch * 1000 + fix;
    }

    return parseVersionScore(cleanCandidate) > parseVersionScore(cleanCurrent);
  }

  /// Проверить наличие новой версии на GitHub
  static Future<AppUpdateInfo?> checkForUpdate() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);

    try {
      final uri = Uri.parse('https://api.github.com/repos/$repoOwner/$repoName/releases/latest');
      final request = await client.getUrl(uri);
      request.headers.set('Accept', 'application/vnd.github.v3+json');
      request.headers.set('User-Agent', 'NeManga-App');

      final response = await request.close();
      if (response.statusCode != 200) {
        return null;
      }

      final responseBody = await response.transform(utf8.decoder).join();
      final json = jsonDecode(responseBody) as Map<String, dynamic>;

      final tagName = (json['tag_name'] as String? ?? '').trim();
      final releaseNotes = json['body'] as String? ?? '';
      final assets = (json['assets'] as List<dynamic>? ?? []);

      final installedVersion = await getCurrentVersion();
      final candidateVersion = tagName.replaceFirst(RegExp(r'^v'), '');
      if (!isNewerVersion(installedVersion, candidateVersion)) {
        return null; // Уже актуальная версия
      }

      // Получаем архитектуру процессора устройства (например, arm64-v8a)
      String deviceAbi = 'arm64-v8a';
      try {
        if (Platform.isAndroid) {
          deviceAbi = (await _channel.invokeMethod<String>('getDeviceAbi')) ?? 'arm64-v8a';
        }
      } catch (_) {}

      // Ищем подходящий APK среди ассетов релиза
      Map<String, dynamic>? selectedAsset;

      // 1. Приоритет: точное совпадение архитектуры (arm64-v8a, armeabi-v7a)
      for (final a in assets) {
        final name = (a['name'] as String? ?? '').toLowerCase();
        if (name.endsWith('.apk') && name.contains(deviceAbi.toLowerCase())) {
          selectedAsset = a as Map<String, dynamic>;
          break;
        }
      }

      // 2. Если не найдено, ищем универсальный APK
      if (selectedAsset == null) {
        for (final a in assets) {
          final name = (a['name'] as String? ?? '').toLowerCase();
          if (name.endsWith('.apk') && name.contains('universal')) {
            selectedAsset = a as Map<String, dynamic>;
            break;
          }
        }
      }

      // 3. Если и универсальный не найден, берем любой первый доступный APK
      if (selectedAsset == null) {
        for (final a in assets) {
          final name = (a['name'] as String? ?? '').toLowerCase();
          if (name.endsWith('.apk')) {
            selectedAsset = a as Map<String, dynamic>;
            break;
          }
        }
      }

      if (selectedAsset == null) {
        return null; // В релизе нет подходящего APK
      }

      return AppUpdateInfo(
        version: candidateVersion,
        tag: tagName,
        releaseNotes: releaseNotes,
        downloadUrl: selectedAsset['browser_download_url'] as String,
        fileName: selectedAsset['name'] as String,
        fileSize: (selectedAsset['size'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      return null;
    } finally {
      client.close();
    }
  }

  /// Скачать и установить APK
  static Future<String> downloadAndInstall({
    required AppUpdateInfo update,
    required void Function(double progress, int downloaded, int total) onProgress,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final updateDir = Directory(p.join(tempDir.path, 'updates'));
    if (!await updateDir.exists()) {
      await updateDir.create(recursive: true);
    }

    final targetFile = File(p.join(updateDir.path, update.fileName));
    if (await targetFile.exists()) {
      await targetFile.delete();
    }

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(update.downloadUrl));
      request.headers.set('User-Agent', 'NeManga-App');
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception('Ошибка загрузки: HTTP ${response.statusCode}');
      }

      final contentLength = response.contentLength > 0 ? response.contentLength : update.fileSize;
      final sink = targetFile.openWrite();
      int downloaded = 0;

      await for (final chunk in response) {
        sink.add(chunk);
        downloaded += chunk.length;
        if (contentLength > 0) {
          onProgress(downloaded / contentLength, downloaded, contentLength);
        }
      }

      await sink.flush();
      await sink.close();

      // Копируем APK в общедоступную папку Загрузки/NeManga,
      // чтобы пользователь мог видеть файл в проводнике и установить его вручную при конфликте подписей
      try {
        final publicDir = await CompressorService.getPublicMangaDirectory();
        final publicApk = File(p.join(publicDir.path, update.fileName));
        await targetFile.copy(publicApk.path);
        await CompressorService.scanMediaFile(publicApk.path);
      } catch (e) {
        debugPrint('Ошибка копирования APK в общедоступную папку: $e');
      }

      // Запускаем нативную установку APK
      if (Platform.isAndroid) {
        final installResult = await _channel.invokeMethod<String>('installApk', {
          'filePath': targetFile.path,
        });
        return installResult ?? 'installerLaunched';
      }

      return 'downloaded';
    } finally {
      client.close();
    }
  }

  /// Нативная установка ранее скачанного APK
  static Future<String> installApkFile(String filePath) async {
    if (Platform.isAndroid) {
      final res = await _channel.invokeMethod<String>('installApk', {
        'filePath': filePath,
      });
      return res ?? 'installerLaunched';
    }
    return 'unsupported';
  }
}
