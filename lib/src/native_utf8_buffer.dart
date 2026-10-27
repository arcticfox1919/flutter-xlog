import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

/// A bounded native scratch allocator for String.toNativeUtf8().
/// One allocation can borrow the reusable buffer. Oversized or overlapping
/// allocations use malloc and are released by free(), never retained here.
/// Callers must free every temporary allocation before disposing the allocator.
final class NativeUtf8Buffer implements ffi.Allocator, ffi.Finalizable {
  /// Allocates [initialCapacity] bytes for reuse, with a [maxCapacity] byte limit.
  /// Defaults to 2 KiB initially and at most 8 KiB of retained native memory.
  /// UTF-8 string allocations include the terminating NUL byte in these limits.
  /// Throws [ArgumentError] unless 1 <= initialCapacity <= maxCapacity.
  NativeUtf8Buffer({int initialCapacity = 2 * 1024, this.maxCapacity = 8 * 1024}) {
    if (initialCapacity < 1 || initialCapacity > maxCapacity) {
      throw ArgumentError('Require 1 <= initialCapacity <= maxCapacity');
    }
    _resize(initialCapacity);
  }

  static final _finalizer = ffi.NativeFinalizer(malloc.nativeFree);

  /// Maximum reusable allocation size in bytes; larger allocations are temporary.
  final int maxCapacity;
  ffi.Pointer<ffi.Uint8> _allocation = ffi.nullptr;
  int _capacity = 0;
  bool _borrowed = false;
  bool _disposed = false;

  /// Current reusable allocation size in bytes, excluding temporary allocations.
  /// Includes space for the terminating NUL and never exceeds [maxCapacity].
  int get capacity => _capacity;

  /// Whether [pointer] is the start of this allocator's reusable buffer.
  /// Callers may cache it until they call [free] or [dispose]. This compares
  /// addresses only; it does not validate arbitrary pointers or detect disposal.
  bool isPooled(ffi.Pointer pointer) => pointer.address == _allocation.address;

  /// Provides [byteCount] bytes of uninitialized native memory.
  /// Borrows the reusable buffer when it is available and the request fits
  /// within [maxCapacity], growing it geometrically within that limit if needed.
  /// Oversized requests and requests made while the buffer is borrowed use
  /// separate malloc allocations; [alignment] is forwarded to malloc for them.
  /// Release each result through [free], never directly through malloc.free.
  /// Throws [StateError] after [dispose].
  @override
  ffi.Pointer<T> allocate<T extends ffi.NativeType>(int byteCount,
      {int? alignment}) {
    if (_disposed) throw StateError('UTF-8 buffer has been disposed');
    if (_borrowed || byteCount > maxCapacity) {
      return malloc.allocate<T>(byteCount, alignment: alignment);
    }
    if (byteCount > _capacity) {
      var next = _capacity;
      while (next < byteCount) {
        next *= 2;
      }
      _resize(next > maxCapacity ? maxCapacity : next);
    }
    _borrowed = true;
    return _allocation.cast<T>();
  }

  /// Releases an allocation returned by this allocator. NULL is allowed.
  /// A pooled allocation becomes available for reuse without freeing its memory;
  /// a temporary allocation is immediately freed through malloc.
  /// Stop using the pointer after this call and release each allocation once.
  @override
  void free(ffi.Pointer pointer) {
    if (isPooled(pointer)) {
      _borrowed = false;
    } else {
      malloc.free(pointer);
    }
  }

  /// Replaces the reusable allocation without copying its previous contents.
  /// Called only during construction or while the buffer is not borrowed, with
  /// a positive capacity no greater than [maxCapacity]. Updates the finalizer's
  /// allocation and external memory size after releasing the previous block.
  void _resize(int capacity) {
    final replacement = malloc<ffi.Uint8>(capacity);
    _finalizer.detach(this);
    malloc.free(_allocation);
    _allocation = replacement;
    _capacity = capacity;
    _finalizer.attach(this, replacement.cast(),
        detach: this, externalSize: capacity);
  }

  /// Immediately frees the reusable buffer and cancels its automatic finalizer.
  /// Invalidates pointers into that buffer; repeated calls do nothing, and
  /// subsequent [allocate] calls throw [StateError]. Temporary allocations are
  /// owned by callers and must be released through [free] before disposal.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _finalizer.detach(this);
    malloc.free(_allocation);
  }
}
