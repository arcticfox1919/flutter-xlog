import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'xlog_platform_interface.dart';

/// An implementation of [XlogPlatform] that uses method channels.
class MethodChannelXlog extends XlogPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('xlog');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
