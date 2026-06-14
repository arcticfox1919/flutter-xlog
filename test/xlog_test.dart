import 'package:flutter_test/flutter_test.dart';
import 'package:xlog/xlog.dart';

void main() {
  group('XLogLevel', () {
    test('原生枚举值往返映射一致', () {
      for (final level in XLogLevel.values) {
        expect(XLogLevel.fromNative(level.native), level);
      }
    });
  });
}
