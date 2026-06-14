import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xlog/xlog.dart';

/// In-memory store for tests.
class _MemoryStore implements XLogUploadStore {
  String? _data;
  int writes = 0;

  @override
  Future<String?> read() async => _data;

  @override
  Future<void> write(String data) async {
    _data = data;
    writes++;
  }
}

/// Uploader that records what it was asked to send and returns a fixed result.
class _FakeUploader {
  _FakeUploader(this.succeed);

  bool succeed;
  final List<List<String>> calls = [];

  Future<bool> call(List<String> filePaths) async {
    calls.add(filePaths);
    return succeed;
  }
}

void main() {
  group('XLogUploadPlanner', () {
    late Directory tmp;
    late _MemoryStore store;
    late _FakeUploader uploader;
    late XLogUploadPlanner planner;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('xlog_upload_test');
      store = _MemoryStore();
      uploader = _FakeUploader(true);
      planner = XLogUploadPlanner(store, uploader.call);
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    String writeFile(String name, String content) {
      final path = '${tmp.path}${Platform.pathSeparator}$name';
      File(path).writeAsStringSync(content);
      return path;
    }

    test('uploads all files on the first run and records them', () async {
      final a = writeFile('app_20260613.xlog', 'aaa');
      final b = writeFile('app_20260614.xlog', 'bbbb');

      final result = await planner.uploadIfNeeded([a, b]);

      expect(result, XLogUploadResult.uploaded);
      expect(uploader.calls, [
        [a, b]
      ]);
      expect(store.writes, 1);
    });

    test('already-uploaded files are skipped next time', () async {
      final a = writeFile('app_20260613.xlog', 'aaa');
      final b = writeFile('app_20260614.xlog', 'bbbb');

      await planner.uploadIfNeeded([a, b]);
      final second = await planner.uploadIfNeeded([a, b]);

      expect(second, XLogUploadResult.nothingToUpload);
      expect(uploader.calls.length, 1); // not called again
    });

    test('a failed upload is not recorded and is retried', () async {
      final a = writeFile('app_20260613.xlog', 'aaa');
      uploader.succeed = false;

      final result = await planner.uploadIfNeeded([a]);
      expect(result, XLogUploadResult.failed);
      expect(store.writes, 0);

      // Retry succeeds, so the uploader is asked again.
      uploader.succeed = true;
      final retry = await planner.uploadIfNeeded([a]);
      expect(retry, XLogUploadResult.uploaded);
      expect(uploader.calls.length, 2);
    });

    test('a changed file (still being written today) is re-uploaded', () async {
      final today = writeFile('app_20260614.xlog', 'bbbb');

      await planner.uploadIfNeeded([today]);

      // Simulate more writes today -> size changes -> fingerprint changes.
      File(today).writeAsStringSync('bbbbXXXX');

      final second = await planner.uploadIfNeeded([today]);
      expect(second, XLogUploadResult.uploaded);
      expect(uploader.calls.last, [today]);
    });

    test('missing / unreadable files are ignored', () async {
      final a = writeFile('app_20260613.xlog', 'aaa');
      final missing = '${tmp.path}${Platform.pathSeparator}nope_20260613.xlog';

      await planner.uploadIfNeeded([a, missing]);

      expect(uploader.calls.single, [a]);
    });

    test('the same file listed twice is uploaded only once', () async {
      final a = writeFile('app_20260613.xlog', 'aaa');

      await planner.uploadIfNeeded([a, a]);

      expect(uploader.calls.single, [a]);
    });

    test('returns nothingToUpload when there are no files', () async {
      final result = await planner.uploadIfNeeded([]);

      expect(result, XLogUploadResult.nothingToUpload);
      expect(uploader.calls, isEmpty);
    });

    test('only new files are uploaded across runs', () async {
      final a = writeFile('app_20260613.xlog', 'aaa');
      final b = writeFile('app_20260614.xlog', 'bbbb');

      await planner.uploadIfNeeded([a]); // a recorded
      final second = await planner.uploadIfNeeded([a, b]); // only b is new

      expect(second, XLogUploadResult.uploaded);
      expect(uploader.calls.last, [b]);
    });
  });
}
