import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('inputFileStream test', () {
    final tempDir = Directory.systemTemp.createTempSync('zip_test');
    final zipFile = File('${tempDir.path}/test.zip');
    
    final encoder = ZipEncoder();
    final archive = Archive();
    archive.addFile(ArchiveFile('img_01.jpg', 4, [10, 20, 30, 40]));
    archive.addFile(ArchiveFile('img_02.png', 4, [50, 60, 70, 80]));
    final bytes = encoder.encode(archive);
    zipFile.writeAsBytesSync(bytes);

    final inputStream = InputFileStream(zipFile.path);
    final decoded = ZipDecoder().decodeStream(inputStream);
    expect(decoded.length, 2);
    expect(decoded[0].name, 'img_01.jpg');
    tempDir.deleteSync(recursive: true);
  });
}
