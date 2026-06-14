
import 'xlog_platform_interface.dart';

class Xlog {
  Future<String?> getPlatformVersion() {
    return XlogPlatform.instance.getPlatformVersion();
  }
}
