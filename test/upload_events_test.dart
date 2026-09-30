import 'dart:io';

import 'package:discord_media_sender/models/models.dart';
import 'package:discord_media_sender/providers/response_providers.dart';
import 'package:discord_media_sender/providers/upload_providers.dart';
import 'package:discord_media_sender/services/media_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ------------------------------------ 2c: event task → UploadUiState

  group('UploadController: event task → UploadUiState (2c)', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('progress event dikemas kini ke state', () {
      final controller = container.read(uploadControllerProvider.notifier);
      controller.applyTaskEvent({
        'event': 'progress',
        'state': 'running',
        'totalBatches': 10,
        'currentBatch': 2,
        'totalFiles': 100,
        'successFiles': 12,
        'failedFiles': 0,
        'uploadedBytes': 4096,
        'totalBytes': 20000,
        'speedMBps': 1.5,
        'message': 'Sending batch 2/10',
      });
      final s = container.read(uploadControllerProvider);
      expect(s.isRunning, isTrue);
      expect(s.progress.currentBatch, 2);
      expect(s.progress.totalBatches, 10);
      expect(s.progress.successFiles, 12);
      expect(s.progress.totalFiles, 100);
      expect(s.progress.message, 'Sending batch 2/10');
    });

    test('paused event → state paused (isRunning kekal true)', () {
      final controller = container.read(uploadControllerProvider.notifier);
      controller.applyTaskEvent({
        'event': 'progress',
        'state': 'paused',
        'totalBatches': 3,
        'currentBatch': 1,
        'totalFiles': 30,
        'successFiles': 10,
        'failedFiles': 0,
        'uploadedBytes': 10,
        'totalBytes': 30,
        'speedMBps': 0.0,
        'message': 'Paused',
      });
      expect(container.read(uploadControllerProvider).state,
          EngineState.paused);
      expect(container.read(uploadControllerProvider).isRunning, isTrue);
    });

    test('finished event → state done + lastFinished + clearSession', () {
      final controller = container.read(uploadControllerProvider.notifier);
      controller.applyTaskEvent({
        'event': 'progress',
        'state': 'running',
        'totalBatches': 2,
        'currentBatch': 1,
        'totalFiles': 20,
        'successFiles': 0,
        'failedFiles': 0,
        'uploadedBytes': 0,
        'totalBytes': 100,
        'speedMBps': 0.0,
        'message': 'x',
      });
      controller.applyTaskEvent({
        'event': 'finished',
        'sessionId': 7,
        'status': 'partial',
        'success': 15,
        'failed': 5,
      });
      final s = container.read(uploadControllerProvider);
      expect(s.isRunning, isFalse);
      expect(s.state, EngineState.done);
      expect(s.lastFinishedStatus, 'partial');
      expect(s.lastFinishedKind, SendResultKind.partial);
      expect(s.activeSessionId, isNull);
      expect(s.progress.failedFiles, 5);
    });

    test('finished cancelled → EngineState.cancelled', () {
      final controller = container.read(uploadControllerProvider.notifier);
      controller.applyTaskEvent({
        'event': 'finished',
        'sessionId': 7,
        'status': 'cancelled',
        'success': 1,
        'failed': 0,
      });
      final s = container.read(uploadControllerProvider);
      expect(s.state, EngineState.cancelled);
      expect(s.lastFinishedKind, SendResultKind.cancelled);
    });

    test('status running (reattach) → UI memperguna progres & sesi', () {
      final controller = container.read(uploadControllerProvider.notifier);
      controller.applyTaskEvent({
        'event': 'status',
        'running': true,
        'sessionId': 42,
        'progress': {
          'state': 'running',
          'totalBatches': 5,
          'currentBatch': 3,
          'totalFiles': 50,
          'successFiles': 20,
          'failedFiles': 1,
          'uploadedBytes': 500,
          'totalBytes': 1000,
          'speedMBps': 2.0,
          'message': 'Sending batch 3/5',
        },
        'logs': <Object>[],
      });
      final s = container.read(uploadControllerProvider);
      expect(s.isRunning, isTrue);
      expect(s.activeSessionId, 42);
      expect(s.progress.currentBatch, 3);
      expect(s.progress.successFiles, 20);
    });

    test('log event → responseLogProvider menerima entri (2c)', () {
      final controller = container.read(uploadControllerProvider.notifier);
      controller.applyTaskEvent({
        'event': 'log',
        'entry': {
          'id': 'e1',
          'batchNumber': 1,
          'totalBatches': 1,
          'fileCount': 1,
          'fileNames': ['a.jpg'],
          'filePaths': ['/a.jpg'],
          'endpoint': 'webhooks/****',
          'method': 'POST',
          'status': 'success',
          'statusCode': 200,
          'latencyMs': 5,
          'uploadBytes': 1,
          'speedMBps': 0.5,
          'attempt': 1,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      });
      expect(container.read(responseLogProvider), hasLength(1));
      expect(container.read(responseLogProvider).first.fileNames, ['a.jpg']);
    });

    test('logs attach → addAll tanpa pendua id (2c)', () {
      final controller = container.read(uploadControllerProvider.notifier);
      Map<String, dynamic> entry(String id) => {
            'id': id,
            'batchNumber': 1,
            'totalBatches': 1,
            'fileCount': 0,
            'fileNames': <String>[],
            'filePaths': <String>[],
            'endpoint': 'webhooks/****',
            'method': 'POST',
            'status': 'success',
            'latencyMs': 1,
            'uploadBytes': 0,
            'speedMBps': 0.0,
            'attempt': 1,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          };
      controller.applyTaskEvent({
        'event': 'logs',
        'entries': [entry('a'), entry('b')],
      });
      controller.applyTaskEvent({
        'event': 'logs',
        'entries': [entry('a'), entry('c')], // 'a' pendua
      });
      final ids = container.read(responseLogProvider).map((e) => e.id).toSet();
      expect(ids, {'a', 'b', 'c'});
      expect(container.read(responseLogProvider), hasLength(3));
    });

    test('startRejected semasa UI running → pulih ke idle + sebab', () async {
      final controller = container.read(uploadControllerProvider.notifier);
      controller.applyTaskEvent({
        'event': 'progress',
        'state': 'running',
        'totalBatches': 1,
        'currentBatch': 0,
        'totalFiles': 5,
        'successFiles': 0,
        'failedFiles': 0,
        'uploadedBytes': 0,
        'totalBytes': 0,
        'speedMBps': 0.0,
        'message': 'Starting...',
      });
      controller.applyTaskEvent({
        'event': 'startRejected',
        'sessionId': 99,
        'reason': 'Configuration is incomplete',
      });
      // Pemulihan sesi berjalan tidak segerak (unawaited) — beri masa.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final s = container.read(uploadControllerProvider);
      expect(s.isRunning, isFalse);
      expect(s.lastFinishedStatus, 'failed');
    });
  });

  // ------------------------------------ 2d: pembersihan sementara ZIP

  group('cleanupZipTempSync: folder sesi resumable DILINDUNGI (2d)', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('dms_cleanup_test');
    });
    tearDown(() {
      tmp.deleteSync(recursive: true);
    });

    test('zipTempDirsFor mengenali folder zip_* sahaja', () {
      final dirs = MediaService.zipTempDirsFor([
        '${tmp.path}/zip_123/photo.jpg',
        '${tmp.path}/DCIM/gallery.jpg', // bukan folder zip_
        '',
      ]);
      expect(dirs, {'${tmp.path}/zip_123'});
    });

    test('folder sesi running dilindungi, yang lain dibuang', () {
      final keep =
          Directory('${tmp.path}/zip_100')..createSync(recursive: true);
      final gone =
          Directory('${tmp.path}/zip_200')..createSync(recursive: true);
      File('${keep.path}/a.jpg').writeAsBytesSync([1]);
      File('${gone.path}/b.jpg').writeAsBytesSync([1]);

      final protected = MediaService.zipTempDirsFor([
        '${keep.path}/a.jpg', // milik sesi yang masih 'running'
      ]);
      MediaService.cleanupZipTempSync(tmp.path, protectedDirs: protected);

      expect(keep.existsSync(), isTrue); // dilindungi (resumable)
      expect(gone.existsSync(), isFalse); // dibuang
    });

    test('baki folder proses lama turut dibuang (kebocoran lama difix)', () {
      final stale = Directory('${tmp.path}/zip_999')..createSync(recursive: true);
      File('${stale.path}/c.jpg').writeAsBytesSync([1]);
      MediaService.cleanupZipTempSync(tmp.path, protectedDirs: const {});
      expect(stale.existsSync(), isFalse);
    });

    test('deleteSessionZipTempDirs menghapus folder sesi tamat sahaja',
        () async {
      final finishedDir = Directory('${tmp.path}/zip_777')
        ..createSync(recursive: true);
      final otherRunning = Directory('${tmp.path}/zip_888')
        ..createSync(recursive: true);

      await MediaService.deleteSessionZipTempDirs(
        ['${finishedDir.path}/x.jpg', '${otherRunning.path}/y.jpg'],
        protectedDirs: {otherRunning.path},
      );
      expect(finishedDir.existsSync(), isFalse);
      expect(otherRunning.existsSync(), isTrue);
    });
  });
}
