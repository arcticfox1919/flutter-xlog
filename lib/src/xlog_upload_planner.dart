import 'dart:convert';
import 'dart:io';

/// Persists the planner's upload bookkeeping as one opaque string. [read] and
/// [write] are a matched pair; the planner owns the format. [read] returns null
/// before anything has been written.
abstract interface class XLogUploadStore {
  Future<String?> read();

  Future<void> write(String data);
}

/// Uploads [filePaths], returning true only if all files were delivered. The
/// planner records them as sent only on true, so false (or a throw) keeps them
/// pending for the next attempt. Batch or stagger the upload inside here as
/// needed.
typedef XLogUploader = Future<bool> Function(List<String> filePaths);

/// The outcome of [XLogUploadPlanner.uploadIfNeeded].
enum XLogUploadResult {
  /// No files needed uploading.
  nothingToUpload,

  /// Files were uploaded and recorded as sent.
  uploaded,

  /// The uploader returned false; files stay pending for a retry.
  failed,
}

/// Uploads xlog log files while skipping ones already sent.
///
/// xlog never cleans up per file, so [XLogInstanceHandle.getLogFiles] returns
/// the whole time window every call and uploading it blindly re-sends unchanged
/// files. This planner drops the duplicates by content fingerprint
/// (`name|size`), tracking what was sent through an [XLogUploadStore].
///
/// Today's file keeps growing, so its size — and fingerprint — changes and it
/// is re-sent; files from past days have a fixed size and upload exactly once.
///
/// ```dart
/// final planner = XLogUploadPlanner(myStore, sendToServer);
/// await planner.uploadIfNeeded(await handle.getLogFiles(timespanDays: 7));
/// ```
class XLogUploadPlanner {
  XLogUploadPlanner(this._store, this._uploader);

  final XLogUploadStore _store;
  final XLogUploader _uploader;

  /// Uploads the not-yet-sent files among [filePaths] and records them on
  /// success. Unchanged files are skipped; missing or unreadable ones are
  /// dropped. Files are recorded only if the uploader returns true, so a failed
  /// upload is retried on the next call. Reads happen off the UI isolate.
  Future<XLogUploadResult> uploadIfNeeded(List<String> filePaths) async {
    final uploaded = _decode(await _store.read());
    final pending = <String>[]; // paths to upload, in input order
    final pendingPrints = <String>{}; // fingerprints of pending + this run

    for (final path in filePaths) {
      final fingerprint = await _fingerprintOf(path);
      if (fingerprint == null) continue; // missing / unreadable
      if (uploaded.contains(fingerprint)) continue; // already sent
      if (!pendingPrints.add(fingerprint)) continue; // duplicate this run
      pending.add(path);
    }

    if (pending.isEmpty) return XLogUploadResult.nothingToUpload;

    final ok = await _uploader(pending);
    if (!ok) return XLogUploadResult.failed;

    await _store.write(_encode(uploaded..addAll(pendingPrints)));
    return XLogUploadResult.uploaded;
  }

  static Future<String?> _fingerprintOf(String path) async {
    try {
      final stat = await FileStat.stat(path);
      if (stat.type == FileSystemEntityType.notFound) return null;
      final name = path.split(Platform.pathSeparator).last;
      return '$name|${stat.size}';
    } on FileSystemException {
      return null;
    }
  }
}

Set<String> _decode(String? stored) {
  if (stored == null || stored.isEmpty) return {};
  try {
    final decoded = jsonDecode(stored);
    if (decoded is List) return decoded.cast<String>().toSet();
  } on FormatException {
    // Corrupt or legacy data: start fresh rather than crash.
  }
  return {};
}

String _encode(Set<String> fingerprints) => jsonEncode(fingerprints.toList());
