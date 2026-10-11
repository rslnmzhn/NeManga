import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

class ImageDimensionHelper {
  static (int, int)? getImageDimensions(String filePath) {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return null;

      final raf = file.openSync(mode: FileMode.read);
      try {
        final header = Uint8List(1024);
        final bytesRead = raf.readIntoSync(header);
        if (bytesRead < 16) return null;

        // 1. PNG: 8 bytes signature, next chunk is IHDR
        // Bytes 16..20: width, bytes 20..24: height (big-endian 32-bit)
        if (header[0] == 0x89 &&
            header[1] == 0x50 &&
            header[2] == 0x4E &&
            header[3] == 0x47) {
          if (bytesRead >= 24) {
            final bd = ByteData.sublistView(header);
            final w = bd.getUint32(16, Endian.big);
            final h = bd.getUint32(20, Endian.big);
            return (w, h);
          }
        }

        // 2. WebP: RIFF....WEBP
        if (header[0] == 0x52 &&
            header[1] == 0x49 &&
            header[2] == 0x46 &&
            header[3] == 0x46 &&
            header[8] == 0x57 &&
            header[9] == 0x45 &&
            header[10] == 0x42 &&
            header[11] == 0x50) {
          final chunk = String.fromCharCodes(header.sublist(12, 16));
          final bd = ByteData.sublistView(header);
          if (chunk == 'VP8 ') {
            if (bytesRead >= 30) {
              final w = bd.getUint16(26, Endian.little) & 0x3FFF;
              final h = bd.getUint16(28, Endian.little) & 0x3FFF;
              return (w, h);
            }
          } else if (chunk == 'VP8L') {
            if (bytesRead >= 25) {
              final val = bd.getUint32(21, Endian.little);
              final w = 1 + (val & 0x3FFF);
              final h = 1 + ((val >> 14) & 0x3FFF);
              return (w, h);
            }
          } else if (chunk == 'VP8X') {
            if (bytesRead >= 30) {
              final w = 1 + (header[24] | (header[25] << 8) | (header[26] << 16));
              final h = 1 + (header[27] | (header[28] << 8) | (header[29] << 16));
              return (w, h);
            }
          }
        }

        // 3. JPEG: 0xFF, 0xD8
        if (header[0] == 0xFF && header[1] == 0xD8) {
          int offset = 2;
          while (offset < bytesRead - 8) {
            if (header[offset] != 0xFF) {
              offset++;
              continue;
            }
            final marker = header[offset + 1];
            // SOF0 (0xC0), SOF1 (0xC1), SOF2 (0xC2)
            if (marker >= 0xC0 && marker <= 0xC2) {
              final bd = ByteData.sublistView(header);
              final h = bd.getUint16(offset + 5, Endian.big);
              final w = bd.getUint16(offset + 7, Endian.big);
              return (w, h);
            }
            // Skip marker segment
            final bd = ByteData.sublistView(header);
            final length = bd.getUint16(offset + 2, Endian.big);
            offset += 2 + length;
          }
        }

        // 4. GIF: GIF87a or GIF89a
        if (header[0] == 0x47 && header[1] == 0x49 && header[2] == 0x46) {
          final bd = ByteData.sublistView(header);
          final w = bd.getUint16(6, Endian.little);
          final h = bd.getUint16(8, Endian.little);
          return (w, h);
        }
      } finally {
        raf.closeSync();
      }
    } catch (_) {}
    return null;
  }
}

void main() {
  test('Image dimension decoding test with sample PNG and real asset', () {
    // 1. Проверяем с ассетом репозитория
    final file = File('assets/icon/app_icon.png');
    if (file.existsSync()) {
      final iconSize = ImageDimensionHelper.getImageDimensions(file.path);
      expect(iconSize, isNotNull);
      expect(iconSize!.$1, 512);
      expect(iconSize.$2, 512);
    }

    // 2. Проверяем со сгенерированным в тесте PNG заголовком
    final tempDir = Directory.systemTemp.createTempSync('dim_test');
    final tempPng = File('${tempDir.path}/sample.png');
    final header = Uint8List(24);
    header.setRange(0, 8, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    // IHDR width = 800, height = 1200
    final bd = ByteData.sublistView(header);
    bd.setUint32(16, 800, Endian.big);
    bd.setUint32(20, 1200, Endian.big);
    tempPng.writeAsBytesSync(header);

    final dims = ImageDimensionHelper.getImageDimensions(tempPng.path);
    expect(dims, isNotNull);
    expect(dims!.$1, 800);
    expect(dims.$2, 1200);

    tempDir.deleteSync(recursive: true);
  });
}
