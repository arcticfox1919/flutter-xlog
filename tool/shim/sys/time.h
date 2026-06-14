// Shim for <sys/time.h> on Windows so ffigen's clang can parse xloggerbase.h.
// ffigen runs clang on the host (Windows) only to extract C API signatures;
// it does not compile for the target. POSIX <sys/time.h> does not exist on
// Windows, so this provides the one thing xloggerbase.h needs: struct timeval.
// This shim affects parsing only — the generated Dart bindings stay
// platform-independent and are unaffected by the exact field types here.
#ifndef XLOG_FFIGEN_SYS_TIME_SHIM_H_
#define XLOG_FFIGEN_SYS_TIME_SHIM_H_

#ifndef _TIMEVAL_DEFINED
#define _TIMEVAL_DEFINED
struct timeval {
    long tv_sec;
    long tv_usec;
};
#endif

#endif  // XLOG_FFIGEN_SYS_TIME_SHIM_H_
