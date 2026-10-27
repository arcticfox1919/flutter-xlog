// Host backend for testing the REAL C ABI adapter extracted by the build tool.
// The fake sink avoids platform I/O; it does not replace the production bridge.
#include "mars/xlog/xlogger_interface.h"
#include <string>

namespace {
int lookups = 0;
int records = 0;
uintptr_t target = 0;
int global_level = kLevelDebug;
int network_level = kLevelDebug;
std::string tag;
std::string message;
XLoggerInfo metadata = XLOGGER_INFO_INITIALIZER;
void (*callback)() = nullptr;
}

extern "C" {
XLOGGER_WRITER_API int test_lookups() { return lookups; }
XLOGGER_WRITER_API int test_records() { return records; }
XLOGGER_WRITER_API uintptr_t test_target() { return target; }
XLOGGER_WRITER_API const char* test_tag() { return tag.c_str(); }
XLOGGER_WRITER_API const char* test_message() { return message.c_str(); }
XLOGGER_WRITER_API int test_level() { return metadata.level; }
XLOGGER_WRITER_API int64_t test_time() { return metadata.timeval.tv_sec; }
XLOGGER_WRITER_API int64_t test_pid() { return metadata.pid; }
XLOGGER_WRITER_API void test_set_level(int level) { network_level = level; }
XLOGGER_WRITER_API void test_set_callback(void (*fn)()) { callback = fn; }

XLOGGER_WRITER_API intmax_t xlogger_pid() { return 101; }
XLOGGER_WRITER_API intmax_t xlogger_tid() { return 202; }
XLOGGER_WRITER_API intmax_t xlogger_maintid() { return 303; }
XLOGGER_WRITER_API TLogLevel xlogger_Level() { return static_cast<TLogLevel>(global_level); }
XLOGGER_WRITER_API void xlogger_SetLevel(TLogLevel level) { global_level = level; }
XLOGGER_WRITER_API int xlogger_IsEnabledFor(TLogLevel level) { return global_level <= level; }
XLOGGER_WRITER_API void xlogger_Write(const XLoggerInfo* info, const char* log) {
    auto hook = callback;
    callback = nullptr;
    if (hook) hook();
    records++;
    tag = info->tag == nullptr ? "" : info->tag;
    message = log;
    metadata = *info;
}
}

namespace mars {
namespace xlog {
mars::comm::XloggerCategory* GetXloggerInstance(const char* prefix) {
    lookups++;
    if (std::string(prefix) == "network") return reinterpret_cast<mars::comm::XloggerCategory*>(uintptr_t(17));
    if (std::string(prefix) == "payment") return reinterpret_cast<mars::comm::XloggerCategory*>(uintptr_t(29));
    return nullptr;
}
bool IsEnabledFor(uintptr_t instance, TLogLevel level) {
    return (instance == 0 ? global_level : network_level) <= level;
}
void XloggerWrite(uintptr_t instance, const XLoggerInfo* info, const char* log) {
    xlogger_Write(info, log);
    target = instance;
}
}  // namespace xlog
}  // namespace mars
