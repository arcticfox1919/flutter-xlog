import 'package:flutter_test/flutter_test.dart';
import 'package:xlog/xlog.dart';
import 'package:xlog/xlog_platform_interface.dart';
import 'package:xlog/xlog_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockXlogPlatform
    with MockPlatformInterfaceMixin
    implements XlogPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final XlogPlatform initialPlatform = XlogPlatform.instance;

  test('$MethodChannelXlog is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelXlog>());
  });

  test('getPlatformVersion', () async {
    Xlog xlogPlugin = Xlog();
    MockXlogPlatform fakePlatform = MockXlogPlatform();
    XlogPlatform.instance = fakePlatform;

    expect(await xlogPlugin.getPlatformVersion(), '42');
  });
}
