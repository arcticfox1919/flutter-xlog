#include "include/xlog/xlog_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "xlog_plugin.h"

void XlogPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  xlog::XlogPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
