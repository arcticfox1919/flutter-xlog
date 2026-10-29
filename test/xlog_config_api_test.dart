import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xlog/src/generated/xlog_config.g.dart' as pigeon;
import 'package:xlog/xlog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = BasicMessageChannel<Object?>(
    'dev.flutter.pigeon.xlog.XlogConfigApi.initialize',
    pigeon.XlogConfigApi.pigeonChannelCodec,
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final received = <pigeon.XlogConfig>[];
  setUp(() {
    received.clear();
    messenger.setMockDecodedMessageHandler<Object?>(channel, (message) async {
      received.add((message! as List<Object?>).single! as pigeon.XlogConfig);
      return <Object?>[null];
    });
  });
  tearDown(() {
    messenger.setMockDecodedMessageHandler<Object?>(channel, null);
  });

  test('initialization sends default policy and existing settings', () async {
    await XLogManager.initialize(
      cacheDir: '/cache',
      logDir: '/logs',
      namePrefix: 'app',
    );
    final config = received.single;
    expect(config.maxFileSizeBytes, 0);
    expect(config.maxAliveTimeSeconds, 864000);
    expect(config.cacheDir, '/cache');
    expect(config.logDir, '/logs');
    expect(config.namePrefix, 'app');
    expect(config.level, pigeon.XlogLevel.debug);
    expect(config.mode, pigeon.XlogMode.async);
    expect(config.consoleLogEnabled, isTrue);
  });

  test('initialization preserves 64-bit policy through the channel', () async {
    const size = (1 << 33) + 123;
    const age = (1 << 32) + 456;
    await XLogManager.initialize(
      cacheDir: '/cache',
      logDir: '/logs',
      namePrefix: 'business',
      level: XLogLevel.warn,
      mode: XLogMode.sync,
      compressMode: XLogCompressMode.zstd,
      compressLevel: -2,
      consoleLogEnabled: false,
      maxFileSizeBytes: size,
      maxAliveTimeSeconds: age,
    );
    final config = received.single;
    expect(config.maxFileSizeBytes, size);
    expect(config.maxAliveTimeSeconds, age);
    expect(config.level, pigeon.XlogLevel.warning);
    expect(config.mode, pigeon.XlogMode.sync);
    expect(config.compressMode, pigeon.XlogCompressMode.zstd);
    expect(config.compressLevel, -2);
    expect(config.consoleLogEnabled, isFalse);
  });

  test('invalid policy fails before contacting the native host', () {
    expect(
      () => XLogManager.initialize(
        cacheDir: '/cache',
        logDir: '/logs',
        namePrefix: 'invalid',
        maxFileSizeBytes: -1,
      ),
      throwsRangeError,
    );
    expect(
      () => XLogManager.initialize(
        cacheDir: '/cache',
        logDir: '/logs',
        namePrefix: 'invalid',
        maxAliveTimeSeconds: 86399,
      ),
      throwsRangeError,
    );
    expect(received, isEmpty);
  });

  test('one-day retention is accepted', () async {
    await XLogManager.initialize(
      cacheDir: '/cache',
      logDir: '/logs',
      namePrefix: 'daily',
      maxAliveTimeSeconds: 86400,
    );
    expect(received.single.maxAliveTimeSeconds, 86400);
  });
}
