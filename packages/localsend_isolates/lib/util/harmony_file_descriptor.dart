import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// The open file descriptor is transferred to Rust; it must not be reused.
class HarmonyFileDescriptor {
  static final _library = DynamicLibrary.open('librust_lib_localsend_app.so');
  static final _create = _library.lookupFunction<Int32 Function(Pointer<Utf8>), int Function(Pointer<Utf8>)>('localsend_create_exclusive');
  static final _close = _library.lookupFunction<Void Function(Int32), void Function(int)>('localsend_close_descriptor');

  static int createExclusive(String path) {
    final nativePath = path.toNativeUtf8();
    try {
      return _create(nativePath);
    } finally {
      malloc.free(nativePath);
    }
  }

  static void close(int descriptor) => _close(descriptor);
}
