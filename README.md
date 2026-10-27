# xlog

English | [简体中文](README.zh-CN.md)

Save your application's logs to files with Tencent Mars xlog. Write from Dart,
Kotlin, Swift, or C/C++. Flutter and native code can share one log destination
or use separate files. Logs are compressed `.xlog` files; encryption is optional.

Dart writes through `dart:ffi`. Initialization and management use Pigeon platform
channels; individual log messages do not go through a platform channel.

## Contents

- [Features and requirements](#features-and-requirements)
- [Installation](#installation)
- [Choose your log destinations](#choose-your-log-destinations)
- [Android startup](#android-startup)
- [iOS startup](#ios-startup)
- [Dart API](#dart-api)
- [Choose a writer and change tags](#instance-writers)
- [How string buffers are reused](#string-buffers)
- [Configuration](#configuration)
- [Files, uploads, and decoding](#files-uploads-and-decoding)
- [Use xlog from local packages and plugins](#use-xlog-from-local-packages-and-plugins)
- [Third-party native libraries](#third-party-native-libraries)
- [JNI and C++ integration](#jni-and-c-integration)
- [Lifecycle and troubleshooting](#lifecycle-and-troubleshooting)
- [Development](#development)

## Features and requirements

| Feature | What it does |
| --- | --- |
| Six levels | Verbose, debug, info, warning, error, fatal; filter messages using a minimum level. |
| Shared native/Dart logging | Initialize once before Flutter, then use the same backend from both sides. |
| Multiple instances | Keep business logs in separate files with separate settings. Dart can write to instances created in Kotlin/Swift. |
| Async/sync modes | Background file writing or synchronous writes on the caller. |
| Memory-mapped buffering | Native caching/recovery reduces the risk of losing buffered messages. It is not a crash reporter or a guarantee against log loss. |
| Compression | zlib and zstd; decode files to read them as text. |
| Encryption | Optional public-key configuration; the private key stays with your decoder. |
| File management | Date-based files, size-based splitting, retention, and native file lookup. |
| Console mirroring | Android logcat / iOS console output when enabled. |
| Native convenience APIs | Kotlin formatted messages/throwable stacks; Swift messages and source metadata. |
| Upload planning | Track uploaded file names and sizes; bring your own storage and uploader. |
| Android 16 KB pages | Native binaries use 16 KB alignment. Other libraries and final APK/AAB packaging must also be compatible. |

| Platform | Current implementation |
| --- | --- |
| Android | API 24+, compile SDK 35, JVM target 17; `arm64-v8a`, `armeabi-v7a`, `x86_64`. |
| iOS | iOS 13+; arm64 device and arm64 simulator. No Intel `x86_64` simulator slice. |
| Dart/Flutter | Dart `>=3.3.0 <4.0.0`; use Flutter with a compatible bundled Dart SDK. |
| Windows/Linux/macOS/web | Logging is not implemented. Desktop folders contain plugin scaffolding. |

Native dependencies are Android `com.github.arcticfox1919:xlog:1.3.7` and iOS
`mars-xlog` `1.3.7`.
Both Dart writing methods below require these matching native dependencies.
Native 1.3.6 does not provide the current per-entry tag interface.

## Installation

Install the published package from [pub.dev](https://pub.dev/packages/xlog):

```sh
flutter pub add xlog
```

Or add a version constraint to your app's `pubspec.yaml`. This example uses the
version in this checkout:

```yaml
dependencies:
  flutter:
    sdk: flutter
  xlog: ^0.2.0
```

```sh
flutter pub get
```

Use a `path` dependency only when developing xlog itself or testing a local change.
The published package is the recommended choice for application projects.

### Android setup

Add JitPack to the host app's dependency repositories, not only the
plugin's standalone settings or `pluginManagement.repositories`. For example,
in `android/build.gradle.kts`, using the example app's layout:

```kotlin
allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }
    }
}
```

If repositories are centralized in `settings.gradle.kts`, add it to
`dependencyResolutionManagement.repositories` instead. Set the app's `minSdk`
to at least 24 and use a JDK/toolchain compatible with JVM target 17.

### iOS setup

Keep Flutter's CocoaPods integration, set the deployment target to iOS 13
or later, and run `pod install` inside `ios` after fetching dependencies. The
plugin already brings in `mars-xlog`; do not manually embed another XCFramework.
Open `Runner.xcworkspace` for native development.

## Choose your log destinations

An instance is one destination with its own configuration:

| Term | Meaning | Example |
| --- | --- | --- |
| Native log instance | Owns the files and compression/encryption settings. Create it during startup. | Default application log and a separate business log. |
| `XLogWriter` | A Dart handle used to write to an existing instance. Keep and reuse it. | `XLogger.defaultWriter` or `XLogger.attach('native_app')`. |
| tag | A label on one entry; change it as needed without changing the destination. | `Payment`, `HTTP`, `HomePage`. |

Usually one default instance and one business instance are enough. Different
tags in the same instance share its files. Create another instance when you need
separate files or settings, rather than a new writer for every tag.

| Kind | Created by | Who can write? |
| --- | --- | --- |
| Global/default | Android `XLog.init`, iOS `XLog.initialize`, or Dart `XLogManager.initialize` | Dart `XLogger`, native global methods, and the global C API. |
| Named | Android/iOS `XLog.openInstance` | Native instance methods and Dart `XLogger.attach(prefix)`. |

For one shared destination, create only the global instance. Dart
`XLogger.i`, Android `XLog.i`, and iOS `XLog.info` then share it.

For one Dart log and one native log, use this arrangement:

| Destination | Prefix used below | Writers |
| --- | --- | --- |
| Global | `flutter_app` | Dart `XLogger`; native global calls also go here. |
| Named | `native_app` | Android `AppLogs.native` / iOS `AppLogs.native`. |

Create both in Application/AppDelegate before SDKs start logging. Do not
initialize again from Dart. Routing depends on the API you call, not language
detection: a native global call still goes to `flutter_app`.

The global `namePrefix` controls filenames; it does not register a named
instance. `getInstance('flutter_app')` does not retrieve the global logger.
Use unique prefixes and dedicated directories. Reopening an existing prefix is
not a reliable configuration-update API.

### Can Dart create a named instance?

The current Dart API has no `openInstance` method. Creating a destination,
writing to it, and managing its files are separate operations:

| Dart operation | What happens |
| --- | --- |
| `XLogManager.initialize(...)` | Opens the one global/default logger. Dart can initialize this logger if native code has not already done so. |
| `XLogManager.getInstance('native_app')` | Gets a management handle for an instance created earlier by Kotlin or Swift. It does not create it. |
| `XLogger.attach(prefix)` | Gets a writer for an existing named instance; does not create the native instance. |
| Create a named instance | Owned by Kotlin/Swift; not exposed in Dart. |

Passing another prefix to `initialize` does not create another independent Dart
logger. For separate Dart/native files, create the global logger and the named
native logger during startup as shown below. Dart can bind either destination
for writing with the native dependencies declared by this plugin.

## Android startup

Add this to the app module, adjusting the package. If you already have an
`Application`, merge the setup into it.

```kotlin
package com.example.app

import android.app.Application
import java.io.File
import xyz.bczl.xlog.LogLevel
import xyz.bczl.xlog.XLog
import xyz.bczl.xlog.XLogInstance

object AppLogs {
    lateinit var native: XLogInstance
        internal set
}

class MyApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        val root = File(filesDir, "xlog")
        fun directory(name: String): String =
            File(root, name).apply { mkdirs() }.absolutePath
        val level = if (BuildConfig.DEBUG) LogLevel.DEBUG else LogLevel.INFO

        // Global destination for Dart; also loads the native libraries.
        XLog.init(
            cacheDir = directory("flutter-cache"),
            logDir = directory("flutter"),
            prefix = "flutter_app",
            level = level,
            mode = XLog.MODE_ASYNC,
        )
        XLog.setConsoleLogEnabled(BuildConfig.DEBUG)
        XLog.setMaxFileSize(8L * 1024 * 1024)
        XLog.setMaxAliveTime(7L * 24 * 60 * 60)

        // Open after init loads libc++_shared.so and libmarsxlog.so.
        AppLogs.native = XLog.openInstance(
            cacheDir = directory("native-cache"),
            logDir = directory("native"),
            prefix = "native_app",
            level = level,
            mode = XLog.MODE_ASYNC,
        )
        AppLogs.native.setConsoleLogEnabled(BuildConfig.DEBUG)
        AppLogs.native.i("Application", "Native logging is ready")
    }
}
```

Register the class in `android/app/src/main/AndroidManifest.xml`:

```xml
<application
    android:name="com.example.app.MyApplication"
    android:label="Your app"
    android:icon="@mipmap/ic_launcher">
    <!-- Keep your existing activities, metadata, and other settings. -->
</application>
```

Replace the existing `android:name`; do not add a second application element.
Import the app's generated `BuildConfig` if its namespace differs from the package.

```kotlin
AppLogs.native.i("Payment", "Payment started")
AppLogs.native.d("Payment", "order=%s, attempt=%d", "A123", 1)
AppLogs.native.w("Download", "progress=100%") // Literal '%' in a plain message.
AppLogs.native.e("Payment", IllegalStateException("Declined"), "Payment failed")

val existing = XLog.getLogInstance("native_app")
val prefixes = XLog.instancePrefixes()
existing?.flush()
XLog.i("Shared", "This global call goes to flutter_app")
```

`v/d/i/w/e/f` have plain and formatted overloads; `e` also accepts a `Throwable`.
Java can call `xyz.bczl.xlog.XLog.i("Tag", "Message")`. Lifecycle/instance methods
on the Kotlin object use `XLog.INSTANCE` from Java.

Android named handles provide `flush`, `flushSync`, `getLevel`,
`setConsoleLogEnabled`, `getLogFiles`, and `close`. The configurable factory below
accepts public-key/compression options at creation; handles do not expose setters
for level, mode, size, or retention.

### Android instance encryption and compression

After `XLog.init` has loaded/installed the backend, create instances natively:

```kotlin
val network = XLog.openInstance(
    cacheDir = "$cacheDir/network",
    logDir = "$filesDir/log/network",
    prefix = "network",
    pubKey = serverPublicKey,
    level = LogLevel.INFO,
    mode = XLog.MODE_ASYNC,
    compressMode = XLog.COMPRESS_ZSTD,
    compressLevel = 3,
    cacheDays = 7
)
network.i("HTTP", "native request completed")
```

`serverPublicKey` is the valid 128-hex-character secp256k1 public key from the
xlog key tool. Keep its private key on the decoding side. Pass `pubKey = ""`
explicitly for an unencrypted configured instance. The original overload without
`pubKey` retains unencrypted zlib defaults and its original method signatures.

Create a configured instance once with a unique prefix. A duplicate prefix,
invalid key format, unsupported backend, or native creation failure throws;
the configured factory does not reuse an existing instance with different
settings. Use `getLogInstance` when you want an existing instance.
Java callers use `Log.openLogInstance(Xlog.XLogConfig)`.

`compressLevel` applies to zstd. The current zlib backend uses fixed level 9,
so `compressLevel = 0` does not disable compression. See
[Configuration](#configuration) for defaults and units.

Dart then binds the existing instance once:

```dart
final httpLog = XLogger.attach('network');
httpLog.i('HTTP', 'Dart request completed');
httpLog.i('Cache', 'Same instance, different tag');
```

Android targets the JitPack dependency
`com.github.arcticfox1919:xlog:1.3.7`, which includes both the configuration
overload and writer C API. Kotlin calls `Log.openLogInstance(config)` directly;
creation and writes use no reflection. Add `https://jitpack.io` to the consuming
app's repositories, as shown in the Android setup above.

## iOS startup

Use `import xlog` for the plugin facade. Add this setup to the Runner target:

```swift
import Foundation
import xlog

enum AppLogs {
  static var native: XLogInstance?

  static func configure() throws {
    let manager = FileManager.default
    let root = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("xlog", isDirectory: true)

    func directory(_ name: String) throws -> String {
      let url = root.appendingPathComponent(name, isDirectory: true)
      try manager.createDirectory(at: url, withIntermediateDirectories: true)
      return url.path
    }

    #if DEBUG
    let level: LogLevel = .debug
    let consoleEnabled = true
    #else
    let level: LogLevel = .info
    let consoleEnabled = false
    #endif

    let flutter = XLogConfiguration(
      logDirectory: try directory("flutter"), namePrefix: "flutter_app"
    )
    flutter.cacheDirectory = try directory("flutter-cache")
    flutter.level = level
    flutter.mode = .async
    flutter.consoleLogEnabled = consoleEnabled
    guard XLog.initialize(configuration: flutter) else {
      throw NSError(domain: "AppLogs", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Cannot open flutter_app"])
    }
    XLog.setMaxFileSize(8 * 1024 * 1024)
    XLog.setMaxAliveTime(7 * 24 * 60 * 60)

    let config = XLogConfiguration(
      logDirectory: try directory("native"), namePrefix: "native_app"
    )
    config.cacheDirectory = try directory("native-cache")
    config.level = level
    config.mode = .async
    config.consoleLogEnabled = consoleEnabled
    guard let instance = XLog.openInstance(configuration: config) else {
      throw NSError(domain: "AppLogs", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Cannot open native_app"])
    }
    instance.setMaxFileSize(8 * 1024 * 1024)
    instance.setMaxAliveTime(7 * 24 * 60 * 60)
    native = instance
    instance.info("AppDelegate", message: "Native logging is ready")
  }
}
```

Call it early in your existing AppDelegate launch method, before logging SDKs:

```swift
override func application(
  _ application: UIApplication,
  didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
) -> Bool {
  do {
    try AppLogs.configure()
  } catch {
    // Choose the initialization-failure policy appropriate for your app.
    NSLog("xlog initialization failed: %@", String(describing: error))
  }
  // Keep existing Flutter/plugin registration and other startup code here.
  return super.application(application, didFinishLaunchingWithOptions: launchOptions)
}
```

Preserve your Flutter template's registration pattern. This repository's example
registers plugins in `didInitializeImplicitFlutterEngine`; older templates may do
so in the launch method. xlog setup does not replace registration.

```swift
AppLogs.native?.info("Payment", message: "Payment started")
AppLogs.native?.log(
  level: .debug, tag: "Payment", message: "Request sent",
  file: #fileID, function: #function, line: #line
)
let existing = XLog.instance(namePrefix: "native_app")
let prefixes = XLog.instanceNamePrefixes
existing?.flush()
XLog.info("Shared", message: "This global call goes to flutter_app")
```

Convenience methods are `verbose/debug/info/warning/error/fatal`. Global/instance
`log` methods accept source metadata. Use Swift interpolation for values/errors;
there is no Kotlin-style throwable overload.

iOS named handles additionally expose writable `level`, `isClosed`,
`setAppenderMode`, `setMaxFileSize`, and `setMaxAliveTime`. Both facades provide
`flush`, `flushSync`, console control, and `close`; iOS instances provide
`logFiles(timeSpanDays:)`. `XLog.closeInstance(namePrefix:)` closes by prefix.
`XLogConfiguration` supports `NSCopying` for deriving another configuration.

### Native global controls at a glance

| Operation | Android `XLog` | iOS `XLog` |
| --- | --- | --- |
| Level | `setLevel(LogLevel.INFO)`, `getLevel()` | `level = .info`, `level` |
| Console | `setConsoleLogEnabled(false)` | `setConsoleLogEnabled(false)` |
| Mode | `setAppenderMode(XLog.MODE_ASYNC)` | `setAppenderMode(.async)` |
| File size | `setMaxFileSize(8L * 1024 * 1024)` | `setMaxFileSize(8 * 1024 * 1024)` |
| Retention | `setMaxAliveTime(7L * 24 * 60 * 60)` | `setMaxAliveTime(7 * 24 * 60 * 60)` |
| Flush | `flush()`, `flushSync()` | `flush()`, `flushSync()` |
| Close | `close()`, `closeInstance(prefix)` | `close()`, `closeInstance(namePrefix:)` |
| Named lookup/list | `getLogInstance(prefix)`, `instancePrefixes()` | `instance(namePrefix:)`, `instanceNamePrefixes` |
| Global files | Not exposed by this facade | `logFiles(timeSpanDays:prefix:)` |

File sizes are in bytes; retention is in seconds. Android also has
`setToastContext(context)` for backend fatal-log Toast
support; pass `null` to clear it and avoid retaining an Activity longer than needed.
The runtime-level and shutdown caveats below also apply to these native methods.

## Dart API

### After native initialization

```dart
import 'package:xlog/xlog.dart';

XLogger.v('UI', 'Building the screen');
XLogger.d('Network', 'Request started');
XLogger.i('App', 'Application is ready');
XLogger.w('Download', 'progress=100%');
XLogger.e('Network', 'Request failed');
XLogger.f('App', 'An unrecoverable application error');
XLogger.log(XLogLevel.info, 'Custom', 'A selected log level');

try {
  throw StateError('Example failure');
} catch (error, stackTrace) {
  XLogger.e('App', '$error\n$stackTrace');
}
```

Messages are plain strings; use interpolation for values. Stack traces are
included only when you add them to the message. Level order is
`verbose < debug < info < warn < error < fatal`. `none` disables output; use it
as a threshold, not a message level.

```dart
XLogger.level = XLogLevel.info; // Changes the global native threshold via FFI.
final current = XLogger.level;

// Argument evaluation happens before a call: guard expensive diagnostics.
if (XLogger.isEnabledFor(XLogLevel.debug)) {
  XLogger.d('State', 'Details: ${buildDiagnosticSnapshot()}');
}
```

`buildDiagnosticSnapshot` represents your own diagnostic code. The current
release has no lazy-message callback API.

<a id="instance-writers"></a>

### Choose a writer and change tags

The native setup examples above create two destinations: the default
`flutter_app` log and the named `native_app` log. Dart can write to both:

```dart
// Keep these writers in your application's logging service.
final appLog = XLogger.defaultWriter;
final businessLog = XLogger.attach('native_app');

appLog.i('Startup', 'Application started');
appLog.i('HomePage', 'Screen opened'); // Different tag, same default files.

businessLog.i('Payment', 'Payment started');
businessLog.i('HTTP', 'Request completed'); // Same business instance.

// This also uses appLog, including its reusable string buffers.
XLogger.i('UI', 'Button tapped');
```

`defaultWriter` is shared: reads return the same writer until
`XLogger.releaseDefaultWriter()` resets the binding.
`attach` creates a Dart writer each time, so call it once per destination and
keep it for repeated logging. Do not call `attach` for each message or each tag.
An empty prefix or a missing native instance throws; it never falls back to the
default destination. The default instance's filename prefix cannot be used to
attach to it: use `defaultWriter` instead.

`XLogManager.getInstance(prefix)` provides management operations such as flush
and file lookup. Its `writer()` method is another way to bind a writing handle;
it also creates a handle each time. Kotlin/Swift still own named-instance creation.

Use each writer in its owning Dart isolate. Keep the shared default writer for
the application lifetime. Call `businessLog.dispose()` when its owner no longer
needs that binding and has stopped writing. This releases the Dart writer's
native handle and string buffers; the native log instance stays open and is
not flushed. If explicitly closing/reopening the native instance, first stop
its Dart/native producers, dispose all its writers, then close it. For the
default binding, use `XLogger.releaseDefaultWriter()` before closing the instance.

Prefixes and tags must not contain NUL (`U+0000`); callers uphold this rule
without a runtime scan. Messages also use C strings: an embedded NUL ends the
message. `writer.write(...)` returning `true` means the entry was submitted to
xlog, not that it is already on disk.

<a id="string-buffers"></a>

### How string buffers are reused

Each writer owns two small native work buffers, one for tag and one for message.
Both the shared default writer and named writers use this mechanism:

| Buffer | Initial size | Maximum retained size |
| --- | ---: | ---: |
| tag | 256 bytes | 512 bytes |
| message | 2 KiB | 8 KiB |

Sizes include the terminating NUL byte and are measured after UTF-8 encoding.
For example, Chinese characters can use several bytes each. These limits are
internal defaults; the public logging API does not expose buffer tuning.

The buffers hold the entry currently being submitted, rather than a queue of
all entries. If you write 100 messages of 1 KiB each, the same 2 KiB message
buffer can handle all 100 in sequence:

1. Encode the first message into the buffer and call C.
2. C consumes the string before returning to Dart.
3. Overwrite the same buffer with the next message and repeat.

With asynchronous logging, xlog's own native buffer keeps the data needed for
later file writes. It does not keep borrowing this Dart-side work buffer.
The number of messages therefore does not grow the retained work buffers.

If a string fits the retained-size limit, its buffer grows only as needed and
is reused afterwards. A larger string uses a separate allocation, freed as soon
as the logging call finishes, including when an entry is filtered out. It does
not enlarge the reusable buffer. The 8 KiB limit controls retained bridge memory;
the native formatter has its own output-size limit for very large entries.

Only the last tag that fits its reusable buffer is cached. Consecutive entries
with that tag reuse its encoding; oversized tags are released after each call.
Changing a tag creates no writer or log instance. At most 8.5 KiB per writer is
retained for these two buffers, excluding Dart objects, temporary encoding data,
and xlog's own native buffers.

Encoding uses `package:ffi`'s `toNativeUtf8` and the Dart SDK encoder. It still
creates temporary Dart bytes and copies them into native memory; reuse reduces
native allocations rather than eliminating all encoding costs. For expensive
messages, check `writer.isEnabledFor(level)` before constructing them.

### Initialize from Dart instead

If native code does not need logs before Flutter starts, Dart can initialize the
global instance. This is an alternative to Application/AppDelegate setup:

```dart
import 'package:flutter/widgets.dart';
import 'package:xlog/xlog.dart';

Future<void> configureLogging({
  required String cacheDirectory,
  required String logDirectory,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  await XLogManager.initialize(
    cacheDir: cacheDirectory,
    logDir: logDirectory,
    namePrefix: 'flutter_app',
    level: XLogLevel.info,
    mode: XLogMode.async,
    consoleLogEnabled: false,
  );
  XLogger.i('App', 'Logging is ready');
}
```

Provide writable app-private directories, for example using your app's
`path_provider` dependency. The plugin does not choose them. Wait for setup to
finish before starting writers. Do not also initialize natively.

### Management

All these methods are static on `XLogManager`:

| API | Purpose |
| --- | --- |
| `initialize(...)` | Open global instance; skip when initialized natively. |
| `flush(sync: false)` | Request flushing; `sync: true` invokes native synchronous flushing. |
| `close()` | Application-owned shutdown; Android's backend also closes named instances. |
| `setLevel(level)` / `getLevel()` | Platform-channel level access; Android delegates to upstream Java, with the caveat below. |
| `setConsoleLogEnabled(enabled)` | Toggle global console output. |
| `setAppenderMode(mode)` | Change global async/sync mode. |
| `setMaxFileSize(bytes)` | Global size-based file splitting. |
| `setMaxAliveSeconds(seconds)` | Global file retention. |
| `getInstance(prefix)` | Get an existing named handle or `null`; does not create it. |
| `instances()` | List named handles; does not include global instance. |

```dart
final nativeLog = await XLogManager.getInstance('native_app');
if (nativeLog != null) {
  final prefix = nativeLog.prefix;
  final level = await nativeLog.getLevel();
  await nativeLog.setConsoleLogEnabled(false);
  await nativeLog.flush();
  final today = await nativeLog.getLogFiles(timespanDays: 0);
  // await nativeLog.close(); // Only when its owner decides shutdown is safe.
}
```

`handle.writer()` is an alternative to `XLogger.attach(handle.prefix)`.
Call it once and retain the writer; each call creates a new Dart writing handle.
Management handles have no setters for instance level, mode, size, or retention.
Before explicitly closing an instance, stop Dart/native producers, dispose its
Dart writers, then close it. Discard old management handles after close/reopen.

## Configuration

| Setting | Dart default | Android Kotlin global default | iOS Swift default |
| --- | --- | --- | --- |
| Log directory | Required `logDir` | Required `logDir` | Required `logDirectory` |
| Cache directory | Required `cacheDir` | Required `cacheDir` | Optional `cacheDirectory` |
| Prefix | Required `namePrefix` | Required `prefix` | Required `namePrefix` |
| Level | `XLogLevel.debug` | `LogLevel.DEBUG` | `.debug` |
| Mode | `XLogMode.async` | `XLog.MODE_ASYNC` | `.async` |
| Public key | `pubKey: ''` | `pubKey = ""` | `publicKey = nil` |
| Compression | `XLogCompressMode.zlib` | `XLog.COMPRESS_ZLIB` | `.zlib` |
| Compression level | `compressLevel: 6` | `compressLevel = 0` | `compressLevel = 6` |
| Cache days | `cacheDays: 0` | `cacheDays = 0` | `cacheDays = 0` |
| Console | `consoleLogEnabled: true` | Set separately | `consoleLogEnabled = true` |
| Loading | Platform integration | `loadLib = true` | CocoaPods linkage |

Android named instances accept encryption/compression settings at creation, but
have fewer runtime setters than the global instance, as explained above.
Use Android `loadLib = false` only if the required native libraries have already
been loaded by the host.

- Directories: dedicate them to xlog; native cleanup operates on files there.
  Do not mix unrelated data into them. Use separate destinations across processes.
- Async/sync: async moves file writing to background work. Formatting,
  compression, locks, and console output can still cost time during the call.
  `flush()` requests work; it does not guarantee a file is ready to upload.
- Compression: select `zstd` / `COMPRESS_ZSTD` / `.zstd` if wanted. The level
  is forwarded to the backend, not a portable “0 means uncompressed” switch. The
  inspected native source fixes zlib to `Z_BEST_COMPRESSION`; zstd uses the supplied
  level. Check your native release before relying on a tuning value.
- Encryption: an empty key disables it. Use the format expected by the
  backend; keep the private key out of the app. Encryption protects files, not
  console output. Key tools are in the [native project](https://github.com/arcticfox1919/xlog).
- Cache days: controls native cache-directory log staging/moving policy.
  `0` uses normal backend behavior. It is separate from file retention, not the
  number of days to retain all logs.
- Splitting/retention: configure after initialization. The inspected backend
  defaults to date-based files, no size splitting, and about 10 days' retention;
  minimum accepted retention is one day. Prefer explicit settings. Size is a
  rotation threshold, not a total disk quota or exact per-file hard cap. Expired
  cleanup is not an exact-time deletion service.

## Files, uploads, and decoding

### Find files

Named files are accessible through native wrappers and Dart handles. Swift also
provides global `XLog.logFiles(timeSpanDays:prefix:)`. Global lookup is not exposed
by Dart `XLogManager` or the Kotlin global facade; use your configured directories
or an app-owned native bridge for those cases.

The day argument is forwarded to the backend. The native source inspected here
interprets `1` as yesterday's date, not an inclusive one-day window, although
some wrapper comments describe a window. To collect today plus the previous six
days without relying on one `7` call, query `0...6` and remove duplicate paths:

```dart
Future<List<String>> recentNativeFiles(XLogInstanceHandle log) async {
  final paths = <String>{};
  for (var day = 0; day < 7; day++) {
    paths.addAll(await log.getLogFiles(timespanDays: day));
  }
  return paths.toList();
}
```

Native equivalents are Android `instance.getLogFiles(0)` and iOS
`instance.logFiles(timeSpanDays: 0)`. Lookup does not flush buffered messages.

### Upload

`XLogUploadPlanner` is not an HTTP client. Implement `XLogUploadStore.read()` and
`write(String)` using persistent app storage. Supply an `XLogUploader`:
`Future<bool> Function(List<String> filePaths)`.

```dart
Future<XLogUploadResult> uploadNativeLogs(
  XLogUploadStore store,
  XLogUploader sendToServer,
) async {
  final log = await XLogManager.getInstance('native_app');
  if (log == null) return XLogUploadResult.nothingToUpload;
  final planner = XLogUploadPlanner(store, sendToServer);
  return planner.uploadIfNeeded(await recentNativeFiles(log));
}
```

Results are `nothingToUpload`, `uploaded`, or `failed` when the uploader returns
`false`. Return `true` only after the whole batch is delivered. Uploader/store
exceptions propagate. Recording happens after delivery and a successful store
write; the planner never deletes files.

Deduplication uses file name + size, not content hashes. Growing files can be
sent again; distinct equal-name/equal-size files can collide. Use separate stores
for destinations, serialize uploads, and add server-side idempotency if needed.
Bookkeeping has no automatic expiry. Prepare a stable file or snapshot after a
coordinated flush when consistency matters; the planner does not freeze active files.

### Decode

`.xlog` files are binary and need decoding before you can read them as text.
Use [xlog_decoder](https://github.com/arcticfox1919/xlog_decoder), a Flutter
desktop GUI for decoding and decrypting xlog files:

- Drag in a log file or ZIP archive, or use the file picker; processing starts
  automatically, including ZIP extraction.
- Decode unencrypted or encrypted logs with zlib/zstd compression. Encrypted
  logs require the private key matching the public key used by the app.
- Save readable `.txt.log` files beside the input file, or choose an output
  directory. Existing files are preserved by numbering duplicate names.

Processing runs locally and requires no Python environment. See the tool's
repository for build instructions and format compatibility.
Command-line alternatives are available in the
[native project's](https://github.com/arcticfox1919/xlog) `mars/xlog/crypt` directory;
choose a script matching your log format, encryption, and compression.

## Use xlog from local packages and plugins

Declaring a Dart dependency and declaring an Android dependency are separate
steps. The following example uses this layout:

```text
workspace/
  my_app/
    pubspec.yaml
    android/
  packages/
    feature_package/
      pubspec.yaml
      lib/
    device_plugin/
      pubspec.yaml
      android/build.gradle.kts
      android/src/main/kotlin/com/example/device_plugin/DevicePlugin.kt
      ios/device_plugin.podspec
```

### Dart code in a local package

If `feature_package/lib` calls `XLogger`, declare xlog in
`packages/feature_package/pubspec.yaml`, even when the app also depends on it:

```yaml
dependencies:
  flutter:
    sdk: flutter
  xlog: ^0.2.0
```

The package can then use the Dart API:

```dart
import 'package:xlog/xlog.dart';

void logFeatureStarted() {
  XLogger.i('FeaturePackage', 'Feature started');
}
```

Run this inside the initialized Flutter app. The package uses the app's existing
global logger; it does not initialize another one. The app adds the local package
with a path dependency, just as it would add any other package.

### Kotlin code in another local Flutter plugin

Suppose `device_plugin` needs to call this plugin's Kotlin `XLog` class.

Step 1: add a normal dependency to `packages/device_plugin/pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  xlog: ^0.2.0
```

Use `dependencies`, not `dev_dependencies`, even if only the plugin's Kotlin
code uses xlog. Flutter needs to include xlog when building the consuming app.

Step 2: in the consuming app's `my_app/pubspec.yaml`, add the local packages.
Keep a direct xlog dependency if the app itself uses its Dart or native APIs:

```yaml
dependencies:
  flutter:
    sdk: flutter
  xlog: ^0.2.0
  feature_package:
    path: ../packages/feature_package
  device_plugin:
    path: ../packages/device_plugin
```

Step 3: declare the Kotlin compile dependency in the local plugin's own Android
build file, `packages/device_plugin/android/build.gradle.kts`:

```kotlin
dependencies {
    compileOnly(project(":xlog"))
}
```

For a Groovy `build.gradle`, use this instead:

```groovy
dependencies {
    compileOnly project(':xlog')
}
```

`:xlog` is the Gradle project created by Flutter for the published xlog plugin.
It is not the underlying Maven AAR. `compileOnly` makes xlog's Kotlin classes
available while compiling `device_plugin`; Flutter includes xlog in the app
because of the pubspec dependency. Recent Flutter versions also wire native
plugin dependencies automatically; the explicit declaration makes this compile
dependency visible in your build file. See Flutter's
[plugin dependency guide](https://docs.flutter.dev/packages-and-plugins/developing-packages#handling-package-interdependencies).

Do not copy xlog's Kotlin files, add paths into the pub cache, or manually include
another `:xlog` project in settings. Use a toolchain compatible with xlog's Android
requirements. A standalone Gradle build of `device_plugin/android` does not have
Flutter's full project graph; build through the app or the plugin's Flutter example.

Step 4: import and call the public Kotlin class:

```kotlin
package com.example.device_plugin

import io.flutter.embedding.engine.plugins.FlutterPlugin
import xyz.bczl.xlog.XLog
import xyz.bczl.xlog.XLogInstance

class DevicePlugin : FlutterPlugin {
    private var nativeLog: XLogInstance? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // Application has already created this named instance.
        nativeLog = XLog.getLogInstance("native_app")
        nativeLog?.i("DevicePlugin", "Plugin is ready")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // The application owns the logger; only drop this plugin's reference.
        nativeLog = null
    }
}
```

For the global destination, call `XLog.i("DevicePlugin", "Message")` instead.
If named lookup returns `null`, check that Application created `native_app` before
Flutter started and that the prefix matches. Do not initialize or close the
shared logger inside each plugin.

`AppLogs` in the startup example belongs to the app module. A plugin should use
`XLog.getLogInstance` or receive a callback; importing the app's `AppLogs` class
would create the wrong dependency direction.

Step 5: run `flutter pub get` in `my_app`, then build the app or sync its Android
project. If `Project with path ':xlog' could not be found` appears, check the local
plugin's normal pubspec dependency and the app's Flutter plugin loader. Do not edit
the generated `.flutter-plugins-dependencies` file.

### Swift code in the same local plugin

Keep the same pubspec dependency and add this inside the plugin's existing
`packages/device_plugin/ios/device_plugin.podspec` block:

```ruby
s.dependency 'xlog'
```

Then its Swift files can call the plugin facade directly:

```swift
import xlog

func logFromPlugin() {
  XLog.info("DevicePlugin", message: "A global log message")
  XLog.instance(namePrefix: "native_app")?.info(
    "DevicePlugin", message: "A named-instance message"
  )
}
```

Run `flutter pub get` in the app and `pod install` in its `ios` directory. As on
Android, the app initializes the logger once. Depending on `xlog` here gives access
to this plugin's Swift classes; depending only on `mars-xlog` gives access to the
lower-level native backend instead.

## Third-party native libraries

A library must call the same backend to share files. Initialization does not
automatically capture `android.util.Log`, `NSLog`, `printf`, Flutter `print`, or
another library's private logger.

### Android Java/Kotlin

If an SDK accepts a logging callback, connect it in the app. For a callback with
signature `(String, String) -> Unit`:

```kotlin
val sdkLogSink: (String, String) -> Unit = { tag, message ->
    AppLogs.native.i(tag, message)
}
// Pass sdkLogSink to the SDK's logging configuration method.
```

This keeps reusable SDKs independent of Flutter. For another Flutter plugin that
wants to import `xyz.bczl.xlog.*`, follow the local-plugin steps above.

An SDK using `com.tencent.mars.xlog.*` can declare the matching native Maven
dependency instead. The plugin uses `implementation`, so other modules should
not assume those Java classes are on their compile classpath. Resolve one backend
version and let the app initialize it. Do not bundle another AAR or open another
global appender inside the SDK.

### iOS Swift/Objective-C

Runner Swift code uses `import xlog`. Objective-C uses the generated facade header:

```objc
#import <xlog/xlog-Swift.h>

[XLog info:@"SDK" message:@"This uses the global instance"];
```

For a callback-based SDK, inject a closure calling
`AppLogs.native?.info(tag, message: message)` for the native destination. Import
the generated Swift header from `.m`/`.mm`, not the bridging header used to build
that same Swift module.

A separate Pod must declare its dependency: Runner's dependencies do not
automatically become that Pod's build dependencies. A native SDK using the
backend directly can add this inside its podspec:

```ruby
s.dependency 'mars-xlog', '1.3.7'
```

CocoaPods can resolve this to the same backend already required by the plugin.
The Pod is `mars-xlog`, its framework/module is `mars`, and the plugin
module is `xlog`. A module using the plugin's Swift facade needs a dependency
on the `xlog` Pod instead. Do not embed another static Mars copy in a prebuilt SDK.
See [CocoaPods dependencies](https://guides.cocoapods.org/syntax/podspec.html#dependency).

For closed-source SDKs without a callback or replaceable logger, the provider
must expose an integration; this plugin cannot redirect their output automatically.

## JNI and C++ integration

C++ calls Mars directly, with no Dart/channel round trip. Initialize from
Application/AppDelegate before allowing native threads to log. Do not reopen
the global appender from JNI or the SDK.

### Android build setup

The AAR includes `libmarsxlog.so` and `libc++_shared.so`, but the inspected build
does not publish Prefab. A Flutter/Maven dependency does not automatically
provide a CMake target or header path.

1. Extract the same AAR version Gradle resolves to a build staging directory.
   AARs are ZIP files; the library is `jni/<abi>/libmarsxlog.so`.
2. Obtain matching headers: `mars/comm/xlogger/xloggerbase.h`, and for named
   instances `mars/xlog/xlogger_interface.h` with its `appender.h` dependency.
3. Link the existing shared library. Do not compile another static xlog backend
   or Mars sources into your SDK.

Add this to the CMake project building your JNI library:

```cmake
# Supply -DXLOG_AAR_DIR=... and -DXLOG_SOURCE_ROOT=...
# AAR_DIR is an extracted AAR; SOURCE_ROOT is matching native source.
add_library(marsxlog SHARED IMPORTED)
set_target_properties(marsxlog PROPERTIES
    IMPORTED_LOCATION "${XLOG_AAR_DIR}/jni/${ANDROID_ABI}/libmarsxlog.so")

add_library(app_native SHARED native_logging.cpp)
target_include_directories(app_native PRIVATE
    "${XLOG_SOURCE_ROOT}/mars/comm/xlogger"
    "${XLOG_SOURCE_ROOT}/mars/xlog")
target_link_libraries(app_native PRIVATE marsxlog)
```

Extend your target if it already exists. Configure `externalNativeBuild.cmake`
in the module, use `c++_shared`, and cover the app's ABIs. Load your JNI library
after `XLog.init`, e.g. `System.loadLibrary("app_native")`.

AGP may package both the imported library and the AAR's copy. For duplicate
`libmarsxlog.so` entries, verify the files are identical before selecting one:

```kotlin
android {
    packaging {
        jniLibs.pickFirsts += "**/libmarsxlog.so"
    }
}
```

Do not hide different versions with `pickFirst`; resolve one compatible C++
runtime too. See Android's
[native linking guide](https://developer.android.com/studio/projects/gradle-external-native-builds).

### iOS build setup

Runner already links `mars` through CocoaPods. Use `.mm` for mixed Objective-C/C++
code. Pure `.cpp` also works when its target has the Mars framework/header search
paths and C++ linkage. A separate Pod declares `mars-xlog`, includes `.mm`/`.cpp`
in `source_files`, and links the C++ standard library as needed. Do not embed the
static XCFramework again.

Headers use `<mars/xlog/xloggerbase.h>` and `<mars/xlog/xlogger_interface.h>`.
Pure C++ includes those headers rather than the generated Swift header.

### C++: global destination

This helper works with the Android paths and iOS framework layout above. Messages
are plain strings, so `%` is literal:

```cpp
#include <sys/time.h>
#if defined(__APPLE__)
#include <mars/xlog/xloggerbase.h>
#else
#include "xloggerbase.h"
#endif

static XLoggerInfo MakeLogInfo(TLogLevel level, const char* tag) {
    XLoggerInfo info = {};
    info.level = level;
    info.tag = tag;
    gettimeofday(&info.timeval, nullptr);
    info.pid = -1;
    info.tid = -1;
    info.maintid = -1;
    return info;
}

void WriteSdkLog(TLogLevel level, const char* tag, const char* message) {
    if (!message || level < kLevelVerbose || level >= kLevelNone ||
        !xlogger_IsEnabledFor(level)) return;
    auto info = MakeLogInfo(level, tag);
    xlogger_Write(&info, message);
}

// After startup: WriteSdkLog(kLevelInfo, "NativeSdk", "progress=100%");
```

In our two-instance setup this goes to `flutter_app`, the global destination.
Fill filename/function/line fields if the SDK callback supplies them.

### C++: named native destination

Look up the separately created `native_app` instance:

```cpp
#include <cstdint>
#if defined(__APPLE__)
#include <mars/xlog/xlogger_interface.h>
#else
#include "xlogger_interface.h"
#endif

// Reuses MakeLogInfo above.
bool WriteNativeSdkLog(const char* tag, const char* message) {
    if (!message) return false;
    auto* instance = mars::xlog::GetXloggerInstance("native_app");
    if (!instance) return false;

    const auto handle = reinterpret_cast<uintptr_t>(instance);
    if (!mars::xlog::IsEnabledFor(handle, kLevelInfo)) return false;
    auto info = MakeLogInfo(kLevelInfo, tag);
    mars::xlog::XloggerWrite(handle, &info, message);
    return true;
}
```

This borrows an instance; it does not create or own it. Stop writers before
release. Do not close concurrently or use its pointer after shutdown. Match
headers, C++ runtime, and binaries: the C++ API is not a version-independent ABI.
The inspected Android export list includes these named-instance symbols; verify
exports if replacing the native build.

Connect an SDK's C log callback to either helper. If adding your own C bridge for
Dart on iOS, retain/export its symbols in the final binary; see
[Flutter's native linking guidance](https://docs.flutter.dev/platform-integration/legacy-ffi-plugin#dynamic-versus-static-linking).
No extra Dart bridge is needed for the C++ calls above.

## Lifecycle and troubleshooting

- Initialize once, early. Start logging SDKs afterwards. Hot restart does not
  restart Application/AppDelegate; do not reopen the global appender from Dart.
- The app owns shutdown. SDKs must not close the shared logger. Closing from
  Dart affects native writers too. Stop named writers before closing them; do
  not assume global flush/close handles all instances identically on both platforms.
- Keep disk waits off the main thread. Native `flushSync` blocks. Current
  Pigeon handlers use the default thread: returning a Dart `Future` does not make
  `flush(sync: true)` safe on the platform main thread. Use async flush normally;
  coordinate critical synchronous flushes in native background work.
- Instances can stay open for the process lifetime; no exit close/flush hook is
  required. On the next launch, initialize them again with the same directories
  and prefixes. Flush as needed before collecting logs for upload. Android
  `Application.onTerminate()` and iOS termination callbacks are not reliable
  places to save the final logs; forced termination can lose buffered data.
- Processes need separate destinations. Android Application runs in each
  app process; use process-specific directories/prefixes. Isolates/Flutter engines
  in the same process share the native global backend.
- Android runtime levels: `XLogManager.setLevel` delegates to `Log.setLevel`.
  In the inspected native source that Java method does not update C++'s level.
  Use Dart `XLogger.level = ...` for the global FFI threshold; native code can call
  `xlogger_SetLevel`. Verify your backend before relying on Kotlin's setter.
- No files: check startup order, writable paths, level, and async flushing.
  Console output alone does not prove a file was written. Initialization may fail
  or ignore repeat opens; do not use it to update settings.
- Android build issues: check host JitPack, ABIs, CMake import, and one native
  version. If release shrinking breaks JNI lookups, retain backend classes/config
  fields in app R8 rules, e.g. `-keep class com.tencent.mars.xlog.** { *; }`.
- iOS build issues: use the Pods workspace and correct XCFramework slice.
  Intel simulators need another native build. For FFI lookup failures, inspect
  release-binary exports and custom linker stripping/export settings.

## Development

Run the regular Dart checks from the plugin directory:

```sh
flutter pub get
flutter analyze
flutter test
```

Only regenerate code when changing the corresponding API:

```sh
dart run pigeon --input pigeon/xlog_config.dart
dart run ffigen --config ffigen.yaml
```

`ffigen.yaml` has a machine-specific LLVM path and Windows header shim. Adjust
them for your machine and verify the target ABI. The plugin declares Android
`com.github.arcticfox1919:xlog:1.3.7` and iOS `mars-xlog` `1.3.7`; use matching
native source and binaries when investigating backend behavior. An older
binary can fail when FFI first resolves a required symbol; there is no
compatibility layer for the 1.3.6 writer interface.

Android uses Gradle remote dependencies; no local AAR loading configuration is
needed. To check app integration, run from `example/`:

```sh
flutter pub get
flutter build apk --debug
```

On iOS, build and verify the CocoaPods/XCFramework integration on macOS.
See [the example app](example) for startup integration and
[the native project](https://github.com/arcticfox1919/xlog) for source, build
scripts, key tools, and decoders. Android final packaging must also satisfy
the [16 KB page-size requirements](https://developer.android.com/guide/practices/page-sizes).

### Optional native bridge tests and benchmarks

These scripts live under `test/`. The host FFI tests require a C++ compiler and
the matching native xlog checkout; without the generated host library those
tests are skipped. Build it, then run the tests:

```sh
dart run test/native/build_writer_test_library.dart --compiler clang++ --mars-root /path/to/xlog
flutter test
```

The helper compiles the production C adapter with a capture sink. Tests cover
instance routing, one-time lookup, filtering, bounded buffer reuse, oversized
temporary allocations, disposal, and synchronous callback reentry.

To measure Dart-to-native bridge overhead using the same sink:

```sh
dart compile exe test/benchmark/benchmark_writer.dart -o .dart_tool/native_writer/benchmark
.dart_tool/native_writer/benchmark 200000
.dart_tool/native_writer/benchmark 200000 --vary-tags
```

On Windows use `benchmark.exe` for the output and run command. These AOT timings
exclude real Android/iOS disk writes, compression, and encryption; they are not
end-to-end logging throughput measurements.

For Java configuration and lifecycle contract checks, use JDK 8 or 17 for
Java 7 source/target support:

```sh
dart run test/java/test_java_instances.dart --mars-root /path/to/xlog --javac /jdk8/bin/javac --java /jdk8/bin/java
```

This tests both native SDK source copies with temporary Android/JNI host stubs.
It covers configuration forwarding, duplicate prefixes, creation failures,
legacy defaults, third-party backends, and concurrent lifecycle operations.
It does not run Android encryption or file I/O.

Flutter builds and these development scripts do not require Python.
`tool/decode_xlog.py` is a separate command-line decoder, not part of the plugin
runtime. For the graphical decoder, see [Decode](#decode).

## License

This plugin uses the [MIT License](LICENSE). Mars xlog and bundled third-party
components retain their respective licenses.
