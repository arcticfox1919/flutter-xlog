import 'dart:convert';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xlog/src/native_utf8_buffer.dart';

void main() {
  test('UTF-8 byte count and terminating NUL determine the pool limit', () {
    final buffer = NativeUtf8Buffer(initialCapacity: 4, maxCapacity: 32);
    addTearDown(buffer.dispose);
    final values = [
      '',
      'a' * 31,
      'a' * 32,
      '中' * 10,
      '中' * 11,
      '😀' * 7,
      '😀' * 8,
      '\ud800',
      'a\u0000b'
    ];
    for (final value in values) {
      final expected = utf8.encode(value);
      final pointer = value.toNativeUtf8(allocator: buffer);
      try {
        final bytes = pointer.cast<Uint8>().asTypedList(expected.length + 1);
        expect(bytes.sublist(0, expected.length), expected);
        expect(bytes.last, 0);
        expect(buffer.isPooled(pointer), expected.length + 1 <= 32);
        expect(buffer.capacity, lessThanOrEqualTo(32));
      } finally {
        buffer.free(pointer);
      }
    }
  });

  test('Small writes reuse the buffer before and after bounded growth', () {
    final buffer = NativeUtf8Buffer(initialCapacity: 4, maxCapacity: 32);
    addTearDown(buffer.dispose);
    final first = 'warm message'.toNativeUtf8(allocator: buffer);
    buffer.free(first);
    for (var i = 0; i < 1000; i++) {
      final pointer = 'short log'.toNativeUtf8(allocator: buffer);
      expect(pointer.address, first.address);
      buffer.free(pointer);
    }
    final expanded = ('a' * 31).toNativeUtf8(allocator: buffer);
    expect(buffer.capacity, 32);
    buffer.free(expanded);
    final small = 'short'.toNativeUtf8(allocator: buffer);
    expect(small.address, expanded.address);
    buffer.free(small);
  });

  test('Oversized allocations never enlarge or replace the retained buffer', () {
    final buffer = NativeUtf8Buffer(initialCapacity: 8, maxCapacity: 30);
    addTearDown(buffer.dispose);
    final small = 'small'.toNativeUtf8(allocator: buffer);
    buffer.free(small);
    for (var i = 0; i < 20; i++) {
      final pointer = ('中' * 10000).toNativeUtf8(allocator: buffer);
      try {
        expect(buffer.isPooled(pointer), isFalse);
        expect(buffer.capacity, 8);
        expect(pointer.toDartString(), '中' * 10000);
      } finally {
        buffer.free(pointer);
      }
    }
    final next = 'next'.toNativeUtf8(allocator: buffer);
    expect(next.address, small.address);
    buffer.free(next);
    final boundary = ('a' * 29).toNativeUtf8(allocator: buffer);
    expect(buffer.isPooled(boundary), isTrue);
    expect(buffer.capacity, 30);
    buffer.free(boundary);
  });

  test('Overlapping allocations preserve borrowed contents and release on error',
      () {
    final buffer = NativeUtf8Buffer(initialCapacity: 8, maxCapacity: 32);
    addTearDown(buffer.dispose);
    final first = 'outer'.toNativeUtf8(allocator: buffer);
    try {
      expect(
          () => using<void>((arena) {
                final nested = 'nested'.toNativeUtf8(allocator: arena);
                final large = ('a' * 100).toNativeUtf8(allocator: arena);
                expect(buffer.isPooled(nested), isFalse);
                expect(buffer.isPooled(large), isFalse);
                expect(first.toDartString(), 'outer');
                expect(nested.toDartString(), 'nested');
                throw StateError('Simulated consumer failure');
              }, buffer),
          throwsStateError);
      expect(first.toDartString(), 'outer');
      expect(buffer.capacity, 8);
    } finally {
      buffer.free(first);
    }
    final next = 'next'.toNativeUtf8(allocator: buffer);
    expect(next.address, first.address);
    buffer.free(next);
  });

  test('Disposal is idempotent and invalid capacity settings are rejected', () {
    final buffer = NativeUtf8Buffer();
    buffer.dispose();
    buffer.dispose();
    expect(() => 'invalid'.toNativeUtf8(allocator: buffer), throwsStateError);
    expect(() => NativeUtf8Buffer(initialCapacity: 0), throwsArgumentError);
    expect(() => NativeUtf8Buffer(maxCapacity: 0), throwsArgumentError);
    expect(() => NativeUtf8Buffer(initialCapacity: 8, maxCapacity: 4),
        throwsArgumentError);
  });
}
