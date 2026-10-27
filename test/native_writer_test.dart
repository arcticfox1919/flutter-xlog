import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xlog/src/log_writer.dart';
import 'package:xlog/src/xlog_native.dart';
import 'package:xlog/xlog.dart';

void main() {
  test('none is never enabled and does not initialize native logging', () {
    expect(XLogger.isEnabledFor(XLogLevel.none), isFalse);
  });
  final suffix = Platform.isWindows
      ? 'dll'
      : Platform.isMacOS
          ? 'dylib'
          : 'so';
  final path = '.dart_tool/native_writer/writer_test.$suffix';
  group('Per-instance writer with per-entry tags', () {
    late ffi.DynamicLibrary library;
    late XLogNative api;
    late int Function() lookups;
    late int Function() records;
    late int Function() target;
    late int Function() lastLevel;
    late ffi.Pointer<Utf8> Function() message;
    late ffi.Pointer<Utf8> Function() tag;
    late void Function(int) setLevel;
    late void Function(ffi.Pointer<ffi.NativeFunction<ffi.Void Function()>>)
        setCallback;
    setUpAll(() {
      library = ffi.DynamicLibrary.open(File(path).absolute.path);
      api = XLogNative(library);
      lookups = library
          .lookupFunction<ffi.Int32 Function(), int Function()>('test_lookups');
      records = library
          .lookupFunction<ffi.Int32 Function(), int Function()>('test_records');
      target = library.lookupFunction<ffi.UintPtr Function(), int Function()>(
          'test_target');
      lastLevel = library
          .lookupFunction<ffi.Int32 Function(), int Function()>('test_level');
      message = library.lookupFunction<ffi.Pointer<Utf8> Function(),
          ffi.Pointer<Utf8> Function()>('test_message');
      tag = library.lookupFunction<ffi.Pointer<Utf8> Function(),
          ffi.Pointer<Utf8> Function()>('test_tag');
      setLevel = library.lookupFunction<ffi.Void Function(ffi.Int32),
          void Function(int)>('test_set_level');
      setCallback = library.lookupFunction<
              ffi.Void Function(
                  ffi.Pointer<ffi.NativeFunction<ffi.Void Function()>>),
              void Function(
                  ffi.Pointer<ffi.NativeFunction<ffi.Void Function()>>)>(
          'test_set_callback');
    });
    setUp(() => setLevel(XLogLevel.debug.native.value));

    test('One global and one named binding accept changing tags without lookup',
        () {
      final before = lookups();
      final global = NativeLogWriter(api);
      final other = NativeLogWriter(api, prefix: 'network');
      addTearDown(global.dispose);
      addTearDown(other.dispose);
      expect(lookups(), before + 1);
      for (var i = 0; i < 1000; i++) {
        final label = 'Module$i';
        global.i(label, 'default $i');
        expect(target(), 0);
        expect(tag().toDartString(), label);
        other.i(label, 'other $i');
        expect(target(), 17);
        expect(tag().toDartString(), label);
        expect(message().toDartString(), 'other $i');
      }
      expect(lookups(), before + 1);
    });

    test('Distinct named instances keep routing separate from tags', () {
      final network = NativeLogWriter(api, prefix: 'network');
      final payment = NativeLogWriter(api, prefix: 'payment');
      addTearDown(network.dispose);
      addTearDown(payment.dispose);
      network.i('SharedTag', 'network');
      expect(target(), 17);
      payment.i('SharedTag', 'payment');
      expect(target(), 29);
      expect(message().toDartString(), 'payment');
    });

    test('Missing or empty named instances never fall back to global', () {
      expect(() => NativeLogWriter(api, prefix: 'missing'), throwsStateError);
      expect(() => NativeLogWriter(api, prefix: ''), throwsArgumentError);
    });

    test(
        'Unicode, percent text, empty and long tags/messages survive buffer reuse',
        () {
      final writer = NativeLogWriter(api, prefix: 'network');
      addTearDown(writer.dispose);
      final values = [
        '',
        '100% %s %d',
        '中文😀',
        'a' * 10000,
        '\ud800',
        'short',
        ''
      ];
      for (final value in values) {
        final expected = value == '\ud800' ? '\ufffd' : value;
        writer.i(value, value);
        expect(tag().toDartString(), expected);
        expect(message().toDartString(), expected);
      }
      final time = library
          .lookupFunction<ffi.Int64 Function(), int Function()>('test_time');
      final pid = library
          .lookupFunction<ffi.Int64 Function(), int Function()>('test_pid');
      expect(time(), greaterThan(0));
      expect(pid(), 101);
    });

    test('Oversized tags and messages survive repeated writes and filtering', () {
      final writer = NativeLogWriter(api, prefix: 'network');
      addTearDown(writer.dispose);
      final largeTag = 'T' * 512;
      final largeMessage = '中' * 3000;
      for (var i = 0; i < 3; i++) {
        expect(writer.write(XLogLevel.info, largeTag, largeMessage), isTrue);
        expect(tag().toDartString(), largeTag);
        expect(message().toDartString(), largeMessage);
      }
      setLevel(XLogLevel.error.native.value);
      final before = records();
      expect(writer.write(XLogLevel.info, largeTag, largeMessage), isFalse);
      expect(records(), before);
      setLevel(XLogLevel.debug.native.value);
      writer.i(largeTag, 'small again');
      expect(tag().toDartString(), largeTag);
      expect(message().toDartString(), 'small again');
      writer.i('ShortTag', 'short');
      writer.i('ShortTag', 'cached tag');
      expect(tag().toDartString(), 'ShortTag');
      expect(message().toDartString(), 'cached tag');
    });

    test('Instance filtering and disposal apply regardless of tag', () {
      final writer = NativeLogWriter(api, prefix: 'network');
      final before = records();
      setLevel(XLogLevel.error.native.value);
      expect(writer.isEnabledFor(XLogLevel.info), isFalse);
      expect(writer.write(XLogLevel.info, 'Filtered', 'message'), isFalse);
      expect(records(), before);
      expect(writer.write(XLogLevel.error, 'Errors', 'accepted'), isTrue);
      setLevel(XLogLevel.debug.native.value);
      expect(writer.write(XLogLevel.info, 'OtherTag', 'accepted'), isTrue);
      writer.dispose();
      writer.dispose();
      expect(writer.write(XLogLevel.info, 'Disposed', 'message'), isFalse);
    });

    test('Nested tags, messages and levels cannot overwrite an outer entry',
        () {
      final writer = NativeLogWriter(api, prefix: 'network');
      addTearDown(writer.dispose);
      final callback = ffi.NativeCallable<ffi.Void Function()>.isolateLocal(() {
        writer.e('NestedTag', 'nested message');
        expect(tag().toDartString(), 'NestedTag');
      });
      addTearDown(callback.close);
      for (final outer in {
        'OuterTag': 'outer' * 2000,
        'OuterTag' * 1000: 'outer' * 20000,
      }.entries) {
        setCallback(callback.nativeFunction);
        writer.i(outer.key, outer.value);
        expect(tag().toDartString(), outer.key);
        expect(message().toDartString(), outer.value);
        expect(lastLevel(), XLogLevel.info.native.value);
        writer.i(outer.key, 'same-tag follow-up');
        expect(tag().toDartString(), outer.key);
        expect(message().toDartString(), 'same-tag follow-up');
      }
    });

    test('C API rejects invalid pointers and levels', () {
      final b = api.bindings;
      expect(b.xlogger_writer_is_enabled(ffi.nullptr, 2), 0);
      expect(
          b.xlogger_writer_write(ffi.nullptr, 2, ffi.nullptr, ffi.nullptr), 2);
      using((arena) {
        final handle = b.xlogger_writer_bind_existing(
            'network'.toNativeUtf8(allocator: arena).cast());
        final label = 'Tag'.toNativeUtf8(allocator: arena).cast<ffi.Char>();
        final text = 'message'.toNativeUtf8(allocator: arena).cast<ffi.Char>();
        try {
          for (final level in [-1, XLogLevel.none.native.value, 99]) {
            expect(b.xlogger_writer_is_enabled(handle, level), 0);
            expect(b.xlogger_writer_write(handle, level, label, text), 2);
          }
          expect(b.xlogger_writer_write(handle, 2, ffi.nullptr, text), 2);
          expect(b.xlogger_writer_write(handle, 2, label, ffi.nullptr), 2);
          expect(b.xlogger_writer_write(handle, 0, label, text), 1);
        } finally {
          b.xlogger_writer_release(handle);
        }
      });
    });

    test('A synchronous hook cannot release its active writer', () {
      final writer = NativeLogWriter(api, prefix: 'network');
      addTearDown(writer.dispose);
      final callback = ffi.NativeCallable<ffi.Void Function()>.isolateLocal(() {
        expect(writer.dispose, throwsStateError);
      });
      addTearDown(callback.close);
      setCallback(callback.nativeFunction);
      expect(writer.write(XLogLevel.info, 'Outer', 'message'), isTrue);
      expect(writer.write(XLogLevel.info, 'NextTag', 'still alive'), isTrue);
      expect(tag().toDartString(), 'NextTag');
    });
  },
      skip: File(path).existsSync()
          ? false
          : 'Run dart run test/native/build_writer_test_library.dart first');
}
