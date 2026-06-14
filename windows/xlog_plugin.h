#ifndef FLUTTER_PLUGIN_XLOG_PLUGIN_H_
#define FLUTTER_PLUGIN_XLOG_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace xlog {

class XlogPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  XlogPlugin();

  virtual ~XlogPlugin();

  // Disallow copy and assign.
  XlogPlugin(const XlogPlugin&) = delete;
  XlogPlugin& operator=(const XlogPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace xlog

#endif  // FLUTTER_PLUGIN_XLOG_PLUGIN_H_
