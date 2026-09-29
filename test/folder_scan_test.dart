import 'dart:io';

import 'package:discord_media_sender/models/models.dart';
import 'package:discord_media_sender/services/media_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('dms_scan_test');
  });

  tearDown(() {
    try {
      tempRoot.deleteSync(recursive: true);
    } catch (_) {}
  });

  File mkFile(String relativePath, {int size = 128}) {
    final f = File(p.join(tempRoot.path, relativePath));
    f.createSync(recursive: true);
    f.writeAsBytesSync(List<int>.filled(size, 65)); // 'A'
    return f;
  }

  group('Imbasan folder (fix paparan media segera)', () {
    test('jumpa media rekursif merentasi subfolder', () async {
      mkFile('a.jpg');
      mkFile('sub/b.mp4');
      mkFile('sub/deep/c.png');

      final res = await MediaService.instance.scanFolder(tempRoot.path);

      expect(res.items.length, 3);
      expect(res.skipped, isEmpty);
      expect(res.items.every((m) => m.status == MediaStatus.ready), isTrue);
      final names = res.items.map((m) => m.name).toSet();
      expect(names, containsAll(['a.jpg', 'b.mp4', 'c.png']));
    });

    test('langkau fail tidak disokong & fail tersembunyi', () async {
      mkFile('nota.txt');
      mkFile('dokumen.pdf');
      mkFile('.tersembunyi.png');
      mkFile('sebenar.webp');

      final res = await MediaService.instance.scanFolder(tempRoot.path);

      expect(res.items.length, 1);
      expect(res.items.first.name, 'sebenar.webp');
    });

    test('jenis betul dikenal pasti (gambar vs video)', () async {
      mkFile('video.mkv');
      mkFile('gambar.gif');

      final res = await MediaService.instance.scanFolder(tempRoot.path);

      final video = res.items.firstWhere((m) => m.name == 'video.mkv');
      final gambar = res.items.firstWhere((m) => m.name == 'gambar.gif');
      expect(video.type, MediaType.video);
      expect(video.mimeType, 'video/x-matroska');
      expect(gambar.type, MediaType.image);
    });

    test('fail melebihi had ditanda oversized & dilangkau', () async {
      // Gambar > 25 MB => melebihi had.
      mkFile('besar.png', size: 25 * 1024 * 1024 + 10);
      mkFile('kecil.jpg', size: 1024);

      final res = await MediaService.instance.scanFolder(tempRoot.path);

      final ready = res.items.where((m) => m.status.canSend).toList();
      expect(ready.length, 1);
      expect(ready.first.name, 'kecil.jpg');
      expect(res.skipped.where((s) => s.contains('besar.png')), isNotEmpty);
    });

    test('folder tidak wujud memberi mesej jelas', () async {
      final res =
          await MediaService.instance.scanFolder(p.join(tempRoot.path, 'tak_ada'));
      expect(res.items, isEmpty);
      expect(res.info, 'Folder not found');
    });

    test('folder kosong tiada item & tiada ralat', () async {
      final res = await MediaService.instance.scanFolder(tempRoot.path);
      expect(res.items, isEmpty);
      expect(res.skipped, isEmpty);
      expect(res.info, isNull);
    });

    test('imbasan kekal berfungsi dijalankan dalam isolate (async)', () async {
      // Ini menguji laluan Isolate.run — hasil mesti boleh dihantar
      // merentasi isolate tanpa ralat.
      for (var i = 0; i < 20; i++) {
        mkFile('sub$i/berulang.jpg');
      }
      final res = await MediaService.instance.scanFolder(tempRoot.path);
      expect(res.items.length, 20);
      // Susunan menaik ikut nama.
      expect(res.items.first.name, contains('berulang'));
    });
  });
}
