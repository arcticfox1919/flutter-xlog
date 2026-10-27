import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'generated/xlog_bindings.dart';
import 'native_utf8_buffer.dart';
import 'xlog_native.dart';
import 'xlog_level.dart';

/// A Dart writing handle bound to one native log instance; each entry has a tag.
/// Binding never creates a log instance, file, or background write thread.
/// Keep the native appender open while using it. dispose() only releases the
/// binding and scratch memory; it never closes or flushes the appender.
abstract class XLogWriter {
  /// Whether this writer's appender currently enables [level]. Returns false
  /// for [XLogLevel.none] or a disposed writer. Checks severity only; native
  /// filters can still drop a log. The result is a snapshot, and write checks
  /// again. Use before expensive message construction; each explicit check is
  /// an extra FFI call. Ordinary logging does not need a separate check.
  bool isEnabledFor(XLogLevel level);

  /// Submits an entry. Returns false when filtered, disposed, or marshalling
  /// fails. A true result means submitted to xlog, not durable on disk.
  bool write(XLogLevel level, String tag, String message);
  void dispose();
  void log(XLogLevel level, String tag, String message) {
    write(level, tag, message);
  }

  void v(String tag, String message) {
    write(XLogLevel.verbose, tag, message);
  }

  void d(String tag, String message) {
    write(XLogLevel.debug, tag, message);
  }

  void i(String tag, String message) {
    write(XLogLevel.info, tag, message);
  }

  void w(String tag, String message) {
    write(XLogLevel.warn, tag, message);
  }

  void e(String tag, String message) {
    write(XLogLevel.error, tag, message);
  }

  void f(String tag, String message) {
    write(XLogLevel.fatal, tag, message);
  }
}

/// Internal implementation; apps use XLogger.defaultWriter or XLogger.attach.
/// Native metadata and fixed fields are allocated once when binding.
/// Normal writes update dynamic fields in place; reentrant writes use a stack
/// copy to preserve outer metadata. Each writer belongs to one Dart isolate.
/// Prefixes and tags must be NUL-free C strings; callers uphold this precondition.
final class NativeLogWriter extends XLogWriter implements ffi.Finalizable {
  NativeLogWriter(this._api, {String? prefix}) {
    if (prefix != null && prefix.isEmpty) {
      throw ArgumentError.value(prefix, 'prefix', 'Must be nonempty');
    }
    _handle = using((arena) => _api.bindings.xlogger_writer_bind_existing(
          prefix == null
              ? ffi.nullptr
              : prefix.toNativeUtf8(allocator: arena).cast(),
        ));
    if (_handle == ffi.nullptr) {
      throw StateError('Native xlog instance is not open: $prefix');
    }
    NativeUtf8Buffer? message;
    NativeUtf8Buffer? tag;
    try {
      tag = NativeUtf8Buffer(initialCapacity: 256, maxCapacity: 512);
      _tag = tag;
      message = NativeUtf8Buffer();
      _message = message;
      _api.finalizer.attach(this, _handle.cast(), detach: this);
    } catch (_) {
      message?.dispose();
      tag?.dispose();
      _api.bindings.xlogger_writer_release(_handle);
      rethrow;
    }
  }
  final XLogNative _api;
  late final NativeUtf8Buffer _message;
  late final NativeUtf8Buffer _tag;
  ffi.Pointer<Utf8> _tagPointer = ffi.nullptr;
  String? _encodedTag;
  late final ffi.Pointer<XLoggerWriter> _handle;
  bool _disposed = false;
  bool _writing = false;

  @override
  bool isEnabledFor(XLogLevel level) =>
      !_disposed &&
      _api.bindings.xlogger_writer_is_enabled(_handle, level.native.value) != 0;

  @override
  bool write(XLogLevel level, String tag, String message) {
    if (_disposed || level == XLogLevel.none) return false;
    // Single-isolate calls are sequential, but a synchronous callback can
    // re-enter. Its rare fallback must not overwrite the outer tag or message.
    if (_writing) {
      try {
        return using((arena) => _submit(
              level,
              tag.toNativeUtf8(allocator: arena),
              message.toNativeUtf8(allocator: arena),
            ));
      } catch (_) {
        return false;
      }
    }
    _writing = true;
    ffi.Pointer<Utf8> messagePointer = ffi.nullptr;
    try {
      // Reuse the last encoding only; changing tags never creates a writer.
      if (tag != _encodedTag) {
        _encodedTag = null;
        _tag.free(_tagPointer);
        _tagPointer = ffi.nullptr;
        _tagPointer = tag.toNativeUtf8(allocator: _tag);
        _encodedTag = tag;
      }
      messagePointer = message.toNativeUtf8(allocator: _message);
      return _submit(level, _tagPointer, messagePointer);
    } catch (_) {
      return false;
    } finally {
      _message.free(messagePointer);
      if (!_tag.isPooled(_tagPointer)) {
        _tag.free(_tagPointer);
        _tagPointer = ffi.nullptr;
        _encodedTag = null;
      }
      _writing = false;
    }
  }

  bool _submit(
      XLogLevel level, ffi.Pointer<Utf8> tag, ffi.Pointer<Utf8> message) {
    return _api.bindings.xlogger_writer_write(
            _handle, level.native.value, tag.cast(), message.cast()) ==
        0;
  }

  @override
  void dispose() {
    if (_disposed) return;
    if (_writing) {
      throw StateError('Cannot dispose a writer from its log callback');
    }
    _disposed = true;
    _api.finalizer.detach(this);
    _api.bindings.xlogger_writer_release(_handle);
    _tag.dispose();
    _message.dispose();
    _tagPointer = ffi.nullptr;
    _encodedTag = null;
  }
}
