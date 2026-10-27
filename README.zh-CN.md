# xlog

[English](README.md) | 简体中文

`xlog` 用来把应用日志写入文件，底层使用腾讯 Mars xlog。
你可以在 Dart、Kotlin、Swift 和 C/C++ 中打日志，也可以把 Flutter 与原生日志分开保存。
日志保存为压缩后的 `.xlog` 文件，需要时可以开启加密。

Dart 写日志走 `dart:ffi`，初始化和管理操作走 Pigeon 生成的平台通道。
不需要把每一条日志都通过平台通道传给原生。

## 目录

- [功能与运行要求](#features-and-requirements)
- [安装](#installation)
- [先决定日志写到哪里](#choose-your-log-destinations)
- [Android：在 Application 初始化](#android-startup)
- [iOS：在 AppDelegate 初始化](#ios-startup)
- [Dart API](#dart-api)
- [选择 writer 和切换 tag](#instance-writers)
- [字符串缓冲区如何复用](#string-buffers)
- [配置说明](#configuration)
- [查找、上传和解码文件](#files-uploads-and-decoding)
- [本地 package 和 plugin 如何使用](#use-xlog-from-local-packages-and-plugins)
- [接入原生第三方库](#third-party-native-libraries)
- [接入 JNI 与 C++](#jni-and-c-integration)
- [生命周期与常见问题](#lifecycle-and-troubleshooting)
- [开发](#development)

<a id="features-and-requirements"></a>

## 功能与运行要求

| 功能 | 能做什么 |
| --- | --- |
| 六个日志级别 | verbose、debug、info、warning、error、fatal；可以设置最低级别，过滤不需要的日志。 |
| Dart 与原生共用日志 | 启动时初始化一次，之后两边都可以写。 |
| 多日志实例 | 把不同业务的日志分开保存、分别配置。Dart 可以写入 Kotlin／Swift 已创建的实例。 |
| 异步／同步模式 | 平时使用后台写文件的异步模式，也可以选择在调用线程执行文件操作的同步模式。 |
| mmap 缓冲 | 原生缓存与恢复机制可以降低缓冲日志丢失的风险，但不保证所有日志都能在进程退出后保留，也不等于崩溃上报。 |
| 压缩 | 支持 zlib、zstd。文件需要解码后才能当作文本阅读。 |
| 加密 | 可以配置公钥加密日志文件，解码端持有对应私钥。 |
| 文件管理 | 按日期生成文件、按大小分卷、设置保留时间、查询日志路径。 |
| 控制台输出 | 可以同时输出到 Android logcat 或 iOS 调试控制台。 |
| 原生日志接口 | Kotlin 支持普通字符串、格式化参数和 Throwable 堆栈；Swift 支持字符串及源码位置信息。 |
| 上传规划 | 根据文件名与大小记录哪些文件已经上传；存储方式和网络上传由应用自己提供。 |
| Android 16 KB 内存页 | 原生库构建包含 16 KB 对齐设置；应用中的其他原生库和最终 APK/AAB 打包也需要兼容。 |

| 平台 | 当前要求与支持范围 |
| --- | --- |
| Android | API 24+，compile SDK 35，JVM target 17；支持 `arm64-v8a`、`armeabi-v7a`、`x86_64`。 |
| iOS | iOS 13+；支持 arm64 真机和 arm64 模拟器，不包含 Intel `x86_64` 模拟器切片。 |
| Dart／Flutter | Dart `>=3.3.0 <4.0.0`；Flutter 自带的 Dart SDK 需要满足这个范围。 |
| Windows／Linux／macOS／web | 尚未实现日志功能。仓库中的桌面目录目前只是插件模板。 |

当前固定依赖 Android `com.github.arcticfox1919:xlog:1.3.7` 和 iOS `mars-xlog` `1.3.7`。
默认写入和命名实例写入都需要匹配这两个原生依赖；原生 1.3.6 不提供当前逐条传 tag 的接口。

<a id="installation"></a>

## 安装

推荐从 [pub.dev](https://pub.dev/packages/xlog) 安装已经发布的版本：

```sh
flutter pub add xlog
```

也可以手动修改应用的 `pubspec.yaml`。下面使用本仓库当前的版本号：

```yaml
dependencies:
  flutter:
    sdk: flutter
  xlog: ^0.2.0
```

```sh
flutter pub get
```

应用项目正常使用 pub.dev 版本即可。只有开发 xlog 本身或测试本地修改时，才需要改用 `path` 依赖。

### Android 配置

把 JitPack 添加到宿主应用的依赖仓库中。只改插件自己的 settings，
或者加到 `pluginManagement.repositories`，都不能替代应用的依赖仓库配置。
如果项目沿用示例中的 `android/build.gradle.kts` 结构，可以这样写：

```kotlin
allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }
    }
}
```

如果应用统一在 `settings.gradle.kts` 管理仓库，就加到其中的
`dependencyResolutionManagement.repositories`。应用 `minSdk` 至少为 24，
JDK／工具链需要支持 JVM target 17。

### iOS 配置

保留 Flutter 的 CocoaPods 集成，将部署版本设为 iOS 13 或更高，
获取 Flutter 依赖后在 `ios` 目录执行 `pod install`。插件已经依赖 `mars-xlog`，
不需要再手动拖入一份 XCFramework。开发原生代码时打开 `Runner.xcworkspace`。

<a id="choose-your-log-destinations"></a>

## 先决定日志写到哪里

先分清三个概念：

| 概念 | 负责什么 | 例子 |
| --- | --- | --- |
| 原生日志实例 | 管理日志文件、压缩和加密配置，在启动时创建。 | 默认应用日志、独立业务日志。 |
| `XLogWriter` | Dart 向已有实例写日志的句柄，获取后长期复用。 | `XLogger.defaultWriter` 或 `XLogger.attach('native_app')`。 |
| tag | 每条日志的内容标签，按需更换，不改变写入目标。 | `Payment`、`HTTP`、`HomePage`。 |

通常一个默认实例加一个业务实例就够用了。同一实例的不同 tag 共用日志文件。
需要独立文件或配置时才创建另一个实例，不需要给每个 tag 创建 writer。

可以把“实例”理解成一个单独的日志输出目标，有自己的目录、文件前缀和配置：

| 类型 | 怎么创建 | 谁可以写入 |
| --- | --- | --- |
| 全局／默认实例 | Android `XLog.init`、iOS `XLog.initialize`，或 Dart `XLogManager.initialize` | Dart `XLogger`、原生全局方法、全局 C API。 |
| 命名实例 | Android／iOS `XLog.openInstance` | 原生实例方法和 Dart `XLogger.attach(prefix)`。 |

如果想让 Dart 和原生写到同一个目标，只创建全局实例即可。
Dart `XLogger.i`、Android `XLog.i`、iOS `XLog.info` 都会使用它。

如果想要 Dart 一份日志、原生一份日志，当前版本推荐这样安排：

| 日志目标 | 本文前缀 | 使用的写入方法 |
| --- | --- | --- |
| 全局实例 | `flutter_app` | Dart `XLogger`；原生全局方法也会写到这里。 |
| 命名实例 | `native_app` | Android `AppLogs.native`／iOS `AppLogs.native`。 |

两者都在 Application／AppDelegate 启动时创建，然后再启动会打日志的 SDK。
Dart 不要再初始化一次。

日志写到哪里，取决于调用了哪个 API，不会自动识别“这条来自 Dart 还是原生”。
例如原生调用 `XLog.i`，仍然会写入全局的 `flutter_app`。

全局 `namePrefix` 只是文件名前缀，不会把全局实例注册成命名实例。
所以 `getInstance('flutter_app')` 不是获取全局日志的方法。
不同实例使用不同前缀和专用目录；不要通过重复打开相同前缀来修改配置。

### Dart 能不能创建命名实例？

当前 Dart API 没有封装 `openInstance`。创建日志目标、写入日志和管理文件是不同的操作：

| Dart 操作 | 实际作用 |
| --- | --- |
| `XLogManager.initialize(...)` | 打开唯一的全局／默认日志。原生没有初始化时，可以由 Dart 来初始化它。 |
| `XLogManager.getInstance('native_app')` | 获取 Kotlin 或 Swift 已经创建的实例，返回用于管理它的对象；不会创建新实例。 |
| `XLogger.attach(prefix)` | 获取原生已有命名实例的 writer，不会创建原生日志实例。 |
| 创建命名实例 | 由 Kotlin/Swift 负责，Dart 不提供创建接口。 |

给 `initialize` 换一个前缀，不会多出一个独立的 Dart 日志实例。
要让 Dart 与原生分别保存日志，使用下面的启动示例：全局实例留给 Dart，命名实例留给原生。
Dart 也可以写入命名实例，使用插件声明的匹配版本原生依赖即可。

<a id="android-startup"></a>

## Android：在 Application 初始化

把下面代码放到 app 模块，包名按实际项目调整。
如果已经有自定义 `Application`，直接合并初始化代码，不要另建第二个。

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

        // 全局实例留给 Dart；这里也会加载原生动态库。
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

        // init 加载 libc++_shared.so 和 libmarsxlog.so 后，再创建命名实例。
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

然后修改 `android/app/src/main/AndroidManifest.xml`：

```xml
<application
    android:name="com.example.app.MyApplication"
    android:label="Your app"
    android:icon="@mipmap/ic_launcher">
    <!-- 保留已有的 activity、metadata 和其他配置。 -->
</application>
```

替换原有的 `android:name` 即可，不要添加第二个 application 节点。
如果应用 namespace 与 Kotlin 包名不同，需要导入正确包下的 `BuildConfig`。

初始化后，原生代码可以这样使用：

```kotlin
AppLogs.native.i("Payment", "Payment started")
AppLogs.native.d("Payment", "order=%s, attempt=%d", "A123", 1)
AppLogs.native.w("Download", "progress=100%") // 普通字符串中的 % 不会触发格式化。
AppLogs.native.e("Payment", IllegalStateException("Declined"), "Payment failed")

val existing = XLog.getLogInstance("native_app")
val prefixes = XLog.instancePrefixes()
existing?.flush()
XLog.i("Shared", "This global call goes to flutter_app")
```

`v/d/i/w/e/f` 均有普通字符串和格式化参数版本；`e` 还支持传入 `Throwable`。
Java 可以直接调用 `xyz.bczl.xlog.XLog.i("Tag", "Message")`；Kotlin object 上
未标记为静态的生命周期、实例管理方法，从 Java 通过 `XLog.INSTANCE` 调用。

Android 命名实例提供 `flush`、`flushSync`、`getLevel`、
`setConsoleLogEnabled`、`getLogFiles`、`close`，现在还可以在创建时指定公钥和压缩配置：

```kotlin
// 先由 XLog.init 加载并安装原生后端；serverPublicKey 来自 xlog 密钥工具。
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
```

公钥为有效的 128 个十六进制字符（64 字节）secp256k1 公钥，私钥留在解码端。
显式传 `pubKey = ""` 可创建不加密但自定义压缩的实例。原来不带 `pubKey` 的重载保持
未加密 zlib 默认值和原有签名。实例不提供级别、模式、大小和保留时间的 setter。

为配置好的实例选择唯一前缀，只创建一次。前缀已占用、公钥格式无效、后端不支持配置或
原生创建失败时，配置工厂会抛出异常，不会悄悄复用设置不同的实例。
需要复用时调用 `getLogInstance`；Java 调用方使用 `Log.openLogInstance(Xlog.XLogConfig)`。
`compressLevel` 在 zstd 中生效；当前 zlib 后端固定使用级别 9，传 `0` 不会关闭压缩。
各参数默认值和单位见[配置说明](#configuration)。

Dart 只需绑定一次：`final log = XLogger.attach('network');`，然后 `log.i('HTTP', '请求完成')`。
Android 目标使用 JitPack 依赖 `com.github.arcticfox1919:xlog:1.3.7`，
其中已包含 Java 配置重载和 writer C API。Kotlin 直接调用
`Log.openLogInstance(config)`，创建和打印均不使用反射。
应用仓库需配置 `https://jitpack.io`，按前面的 Android 接入示例即可使用。

<a id="ios-startup"></a>

## iOS：在 AppDelegate 初始化

通过 `import xlog` 使用插件提供的 Swift 接口。把下面的初始化代码加入 Runner target：

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

在现有 AppDelegate 的启动方法中尽早调用，再初始化依赖日志的 SDK：

```swift
override func application(
  _ application: UIApplication,
  didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
) -> Bool {
  do {
    try AppLogs.configure()
  } catch {
    // 根据应用需要处理初始化失败。
    NSLog("xlog initialization failed: %@", String(describing: error))
  }
  // 保留已有的 Flutter 插件注册与其他启动代码。
  return super.application(application, didFinishLaunchingWithOptions: launchOptions)
}
```

保留项目原来的 Flutter 插件注册方式。本仓库示例在
`didInitializeImplicitFlutterEngine` 中注册；旧版模板可能直接在启动方法里注册。
xlog 初始化不能替代这些注册步骤。

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

六个便捷方法分别是 `verbose/debug/info/warning/error/fatal`。
全局和实例的 `log` 方法都能传文件名、函数名和行号。
Swift 的变量和错误信息通过字符串插值拼接，没有 Kotlin 那样的 Throwable 重载。

与 Android 不同，iOS 命名实例还支持可写的 `level`、`isClosed`、
`setAppenderMode`、`setMaxFileSize`、`setMaxAliveTime`。
全局和实例都有 `flush`、`flushSync`、控制台设置和 `close`；实例通过
`logFiles(timeSpanDays:)` 查文件。也可以用 `XLog.closeInstance(namePrefix:)`
按前缀关闭。`XLogConfiguration` 支持 `NSCopying`，可以先复制配置，再为新实例调整参数。

### 原生全局管理接口速查

| 操作 | Android `XLog` | iOS `XLog` |
| --- | --- | --- |
| 级别 | `setLevel(LogLevel.INFO)`、`getLevel()` | `level = .info`、`level` |
| 控制台 | `setConsoleLogEnabled(false)` | `setConsoleLogEnabled(false)` |
| 模式 | `setAppenderMode(XLog.MODE_ASYNC)` | `setAppenderMode(.async)` |
| 文件大小 | `setMaxFileSize(8L * 1024 * 1024)` | `setMaxFileSize(8 * 1024 * 1024)` |
| 保留时间 | `setMaxAliveTime(7L * 24 * 60 * 60)` | `setMaxAliveTime(7 * 24 * 60 * 60)` |
| 刷盘 | `flush()`、`flushSync()` | `flush()`、`flushSync()` |
| 关闭 | `close()`、`closeInstance(prefix)` | `close()`、`closeInstance(namePrefix:)` |
| 查找／列出命名实例 | `getLogInstance(prefix)`、`instancePrefixes()` | `instance(namePrefix:)`、`instanceNamePrefixes` |
| 全局文件查询 | 此封装未提供 | `logFiles(timeSpanDays:prefix:)` |

文件大小单位是字节，保留时间单位是秒。
Android 还有 `setToastContext(context)`，用于后端的 fatal 日志 Toast 支持；
传入 `null` 可清除引用，避免长时间持有 Activity。后面的级别兼容性和关闭注意事项同样适用。

## Dart API

### 原生初始化后直接写日志

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

Dart 消息是普通字符串，变量使用字符串插值。需要堆栈时，像上面一样把
`stackTrace` 放入消息中，插件不会自动捕获它。

级别从低到高是 `verbose < debug < info < warn < error < fatal`。
`none` 用来关闭输出，应作为过滤阈值，不要作为某条消息的级别。

```dart
XLogger.level = XLogLevel.info; // 通过 FFI 修改全局原生过滤级别。
final current = XLogger.level;

// 实参会先求值；昂贵的诊断信息应先判断级别。
if (XLogger.isEnabledFor(XLogLevel.debug)) {
  XLogger.d('State', 'Details: ${buildDiagnosticSnapshot()}');
}
```

上面的 `buildDiagnosticSnapshot` 代表应用自己的诊断代码。
函数实参会在调用前求值；如果构造消息比较昂贵，就先判断级别。
当前版本没有延迟生成消息的回调接口。

<a id="instance-writers"></a>

### 选择 writer 和切换 tag

上面的原生启动示例创建了两个日志目标：默认的 `flutter_app` 和命名实例 `native_app`。
Dart 可以分别向它们写日志：

```dart
// 放在应用的日志服务中保存，后续一直复用。
final appLog = XLogger.defaultWriter;
final businessLog = XLogger.attach('native_app');

appLog.i('Startup', '应用启动');
appLog.i('HomePage', '打开页面'); // 换了 tag，仍写入同一份默认日志。

businessLog.i('Payment', '开始支付');
businessLog.i('HTTP', '请求完成'); // 都写入同一个业务实例。

// 这条同样复用 appLog，包括它的字符串缓冲区。
XLogger.i('UI', '点击按钮');
```

`defaultWriter` 是共享的，在调用 `XLogger.releaseDefaultWriter()` 重置绑定前，
反复获取会返回同一个 writer。
`attach` 每次都会创建一个 Dart writer，因此每个日志目标绑定一次，保留后反复使用即可。
不要每打印一条日志或每换一个 tag 就调用 `attach`。前缀为空或原生实例不存在时会抛错，
不会改写到默认实例。默认实例的文件前缀不能用于 `attach`，访问它应使用 `defaultWriter`。

`XLogManager.getInstance(prefix)` 获取的是管理句柄，用来 flush、查找文件等。
也可以调用它的 `writer()` 获取写入句柄；这个方法每次同样会新建 Dart writer。
命名原生日志实例仍由 Kotlin／Swift 创建。

每个 writer 在所属的 Dart isolate 中使用。共享的默认 writer 通常与应用同寿命。
业务 writer 的拥有者不再需要该绑定、并已停止写入后，可以调用 `businessLog.dispose()`。
它只释放写入句柄和字符串缓冲区，原生日志实例仍然存在，也不会因此 flush。
如果需要主动关闭、重建原生实例，顺序是：停止该实例的 Dart 和原生写入，dispose 所有
绑定的 writer，最后关闭原生实例。默认写入句柄使用 `XLogger.releaseDefaultWriter()` 释放。

prefix 和 tag 不得包含 NUL（`U+0000`），由调用方保证，运行时不扫描检查。
message 也使用 C 字符串，遇到内嵌 NUL 就结束。`writer.write(...)` 返回 `true` 表示
已提交给 xlog，不代表已经写入磁盘。

<a id="string-buffers"></a>

### 字符串缓冲区如何复用

每个 writer 都有两块原生工作内存，分别处理 tag 和 message。默认 writer 和命名实例
writer 都使用这套机制：

| 缓冲区 | 初始容量 | 最大常驻容量 |
| --- | ---: | ---: |
| tag | 256 字节 | 512 字节 |
| message | 2 KiB | 8 KiB |

容量按 UTF-8 编码后的字节数计算，包含末尾的 NUL 结束字节；一个汉字可能占多个字节。
这是内部默认配置，公共日志接口暂不提供容量设置参数。

这两块内存每次只处理正在提交的那一条日志，不会把所有历史日志堆在里面。
例如连续打印 100 条、每条 1 KiB 的消息，同一块 2 KiB 的 message 缓冲区就能反复使用：

1. 把第 1 条消息编码到缓冲区，调用 C 接口。
2. C 在返回 Dart 之前读取完这条字符串。
3. 第 2 条覆盖同一块缓冲区，继续提交，之后依次复用。

异步写文件所需的数据由 xlog 自己的原生缓冲保存，不会继续借用这块 Dart 侧工作内存。
所以打印条数增加，不会让这里的常驻缓冲不断变大。

单条字符串在常驻上限内时，缓冲区按需扩容，之后继续复用。超出上限时，为这一条单独
申请临时内存，日志调用结束后立即释放，包括被级别过滤的情况，不会撑大常驻缓冲。
这里的 8 KiB 限制的是桥接层保留的工作内存；超长日志最终能输出多少，还受原生格式化器
自身的长度限制影响。

tag 只缓存上一次能够放进复用缓冲区的编码，连续相同 tag 可以直接复用；超大 tag 每次
提交后都会释放。换 tag 不会创建新 writer 或日志实例。每个 writer 的这两块常驻缓冲
合计最多 8.5 KiB，不包含 Dart 对象、临时编码数据及 xlog 后端自己的原生缓冲。

编码直接复用 `package:ffi` 的 `toNativeUtf8` 和 Dart 标准库，会产生临时 Dart 字节数组，
再复制到原生内存。复用缓冲减少的是原生分配次数，编码本身仍有成本；构造消息较昂贵时，
先调用 `writer.isEnabledFor(level)` 再拼接内容。

### 也可以选择由 Dart 初始化

如果原生在 Flutter 启动前不需要打日志，可以改由 Dart 创建全局实例。
这是另一种初始化方式，不要与 Application／AppDelegate 初始化重复使用：

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

目录由应用提供，例如在应用中使用 `path_provider` 获取可写的私有目录；
插件不会自动选择目录。等待初始化完成后，再启动需要日志的代码。

### 管理接口

以下方法均为 `XLogManager` 静态方法：

| API | 用途 |
| --- | --- |
| `initialize(...)` | 打开全局实例；原生已经初始化时不要再调用。 |
| `flush(sync: false)` | 请求刷盘；`sync: true` 调用原生同步刷盘。 |
| `close()` | 应用统一关闭日志。Android 后端还会关闭命名实例。 |
| `setLevel(level)`／`getLevel()` | 通过平台通道管理级别；Android 转发到上游 Java，注意下方兼容性说明。 |
| `setConsoleLogEnabled(enabled)` | 控制全局日志是否也输出到控制台。 |
| `setAppenderMode(mode)` | 切换全局同步／异步模式。 |
| `setMaxFileSize(bytes)` | 设置全局文件分卷阈值，单位为字节。 |
| `setMaxAliveSeconds(seconds)` | 设置全局文件保留时间，单位为秒。 |
| `getInstance(prefix)` | 获取已经存在的命名实例句柄；不存在时返回 `null`，不会创建。 |
| `instances()` | 列出命名实例句柄，不包含全局实例。 |

```dart
final nativeLog = await XLogManager.getInstance('native_app');
if (nativeLog != null) {
  final prefix = nativeLog.prefix;
  final level = await nativeLog.getLevel();
  await nativeLog.setConsoleLogEnabled(false);
  await nativeLog.flush();
  final today = await nativeLog.getLogFiles(timespanDays: 0);
  // await nativeLog.close(); // 仅在应用确认可以安全关闭时执行。
}
```

`handle.writer()` 与 `XLogger.attach(handle.prefix)` 都可以获取 writer。
调用一次后保留复用；每次调用都会创建新的 Dart 写入句柄。管理句柄不提供实例级别、模式、
大小或保留时间的 setter。主动关闭实例时，先停止 Dart 和原生写入，再 dispose 绑定的
全部 Dart writer，最后关闭实例。实例关闭、重开后应丢弃旧管理句柄。

<a id="configuration"></a>

## 配置说明

| 配置 | Dart 默认值 | Android Kotlin 全局默认值 | iOS Swift 默认值 |
| --- | --- | --- | --- |
| 日志目录 | 必填 `logDir` | 必填 `logDir` | 必填 `logDirectory` |
| 缓存目录 | 必填 `cacheDir` | 必填 `cacheDir` | 可选 `cacheDirectory` |
| 前缀 | 必填 `namePrefix` | 必填 `prefix` | 必填 `namePrefix` |
| 最低级别 | `XLogLevel.debug` | `LogLevel.DEBUG` | `.debug` |
| 写入模式 | `XLogMode.async` | `XLog.MODE_ASYNC` | `.async` |
| 公钥 | `pubKey: ''` | `pubKey = ""` | `publicKey = nil` |
| 压缩算法 | `XLogCompressMode.zlib` | `XLog.COMPRESS_ZLIB` | `.zlib` |
| 压缩级别 | `compressLevel: 6` | `compressLevel = 0` | `compressLevel = 6` |
| 缓存天数 | `cacheDays: 0` | `cacheDays = 0` | `cacheDays = 0` |
| 控制台 | `consoleLogEnabled: true` | 单独设置 | `consoleLogEnabled = true` |
| 库加载 | 平台集成负责 | `loadLib = true` | CocoaPods 链接 |

Android 命名实例的创建配置与原生后端一致，运行时 setter 仍较少，详见前面的 Android 部分。
只有宿主已经加载所需原生库时，Android 才应传入 `loadLib = false`。

- 目录：使用 xlog 专用目录。原生会在目录中清理文件，不要混放其他业务数据。
  多进程也不要共用同一个日志目标。
- 同步与异步：异步模式把文件写入交给后台，但格式化、压缩、加锁和控制台输出
  仍可能消耗调用线程的时间。`flush()` 只是发起请求，不代表文件已经准备好上传。
- 压缩：可以选择 `zstd`／`COMPRESS_ZSTD`／`.zstd`。压缩级别会转交给后端，
  不能统一理解成“0 就是不压缩”。本次查阅的原生源码中，zlib 固定使用
  `Z_BEST_COMPRESSION`，zstd 才使用传入级别；依赖具体调优值前，请核对实际原生版本。
- 加密：公钥为空时关闭。密钥格式遵循后端要求，私钥留在解码端，不要放进应用。
  加密针对文件，不会保护同时输出到控制台的明文。密钥工具见
  [原生项目](https://github.com/arcticfox1919/xlog)。
- 缓存天数：控制原生日志在缓存目录暂存、搬移的策略；`0` 使用后端通常行为。
  它和日志文件保留时间是两件事，不代表所有日志只保留这么多天。
- 分卷与保留：初始化后设置。查阅的后端默认按日期生成文件、不按大小分卷、
  大约保留 10 天，接受的最短保留时间为一天。建议显式配置。文件大小是分卷阈值，
  不是总磁盘配额，也不是绝不超出的文件硬上限；过期清理也不是精确到秒的定时删除。

<a id="files-uploads-and-decoding"></a>

## 查找、上传和解码文件

### 查找文件

命名实例可以通过原生封装和 Dart 句柄查询文件。Swift 还提供全局
`XLog.logFiles(timeSpanDays:prefix:)`；Dart `XLogManager` 和 Kotlin 全局封装
目前没有对应的全局文件查询方法，应使用已配置的目录或应用自建的原生桥接。

天数参数会直接转给后端。本次查阅的原生源码把 `1` 解释为“昨天这一天”，
而不是包含最近一天的窗口，虽然部分封装注释写成了时间范围。
为了获取今天及之前六天，可以分别查询 `0...6` 并按路径去重，不依赖一次传 `7`：

```dart
Future<List<String>> recentNativeFiles(XLogInstanceHandle log) async {
  final paths = <String>{};
  for (var day = 0; day < 7; day++) {
    paths.addAll(await log.getLogFiles(timespanDays: day));
  }
  return paths.toList();
}
```

原生对应 Android `instance.getLogFiles(0)` 和 iOS
`instance.logFiles(timeSpanDays: 0)`。查询文件不会顺便刷盘。

### 上传

`XLogUploadPlanner` 不负责 HTTP。实现 `XLogUploadStore.read()`、`write(String)`
来持久保存上传记录，再传入一个 `XLogUploader`：
`Future<bool> Function(List<String> filePaths)`。

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

返回值是 `nothingToUpload`、`uploaded`，或者上传回调返回 `false` 时的 `failed`。
只有整批文件都送达后，回调才应该返回 `true`。上传器或存储抛出的异常会继续传给调用方。
上传成功且记录写入成功后，文件才被记作已发送；规划器不会删除日志文件。

当前去重依据是文件名 + 大小，不是内容哈希。正在增长的文件可以再次上传，
同名同大小的不同文件也可能被误判。不同日志目标应使用不同存储记录，上传调用串行执行，
有需要时让服务端支持幂等。记录不会自动过期清理。
需要内容一致时，在协调刷盘后准备稳定文件或快照；规划器不会冻结正在写入的文件。

### 解码

`.xlog` 是二进制文件，需要解码后才能作为文本阅读。
推荐使用 [xlog_decoder](https://github.com/arcticfox1919/xlog_decoder)，一个基于 Flutter
的桌面图形化日志解码、解密工具：

- 拖入日志文件或 ZIP 压缩包，或点击按钮选择文件，自动完成解压、解密和解码。
- 支持未加密、加密日志及 zlib／zstd 压缩；加密日志填写与应用公钥配对的私钥。
- 生成可读的 `.txt.log` 文件，默认保存在输入文件同级目录，也可指定输出目录；同名文件
  自动编号，不覆盖已有文件。

全程在本地处理，无需 Python 环境。运行、构建方式和格式兼容范围见工具仓库。
如需命令行脚本，也可使用[原生项目](https://github.com/arcticfox1919/xlog)的
`mars/xlog/crypt`，选择与日志格式、加密和压缩方式匹配的脚本。

<a id="use-xlog-from-local-packages-and-plugins"></a>

## 本地 package 和 plugin 如何使用

需要分清两个地方：`pubspec.yaml` 管 Flutter 包依赖，Android 的 Gradle 文件管 Kotlin
编译依赖。下面用这个目录结构举例：

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

### 本地 package 的 Dart 代码打日志

假设 `feature_package/lib` 要调用 `XLogger`，就在
`packages/feature_package/pubspec.yaml` 中声明依赖，不能只在 app 里添加：

```yaml
dependencies:
  flutter:
    sdk: flutter
  xlog: ^0.2.0
```

然后在这个 package 的 Dart 文件中调用：

```dart
import 'package:xlog/xlog.dart';

void logFeatureStarted() {
  XLogger.i('FeaturePackage', 'Feature started');
}
```

这些代码在已经初始化日志的 Flutter 应用中运行，使用的是应用已有的全局日志，
package 不需要再初始化。app 像平时一样用 `path` 依赖这个本地 package 即可。

### 本地 Flutter plugin 的 Kotlin 代码打日志

假设 `device_plugin` 想使用当前 xlog 插件中的 Kotlin `XLog` 类，按下面几步配置。

第一步，在 `packages/device_plugin/pubspec.yaml` 中添加普通依赖：

```yaml
dependencies:
  flutter:
    sdk: flutter
  xlog: ^0.2.0
```

放在 `dependencies`，不要放在 `dev_dependencies`。即使只有 Kotlin 使用 xlog，
也要声明这个 Flutter 依赖，这样宿主 app 构建时才会带上它。

第二步，在宿主的 `my_app/pubspec.yaml` 中引入这些本地包。
app 自己也调用 xlog 的 Dart 或原生 API 时，保留对 xlog 的直接依赖：

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

第三步，修改这个本地 plugin 自己的 Android 构建文件，
即 `packages/device_plugin/android/build.gradle.kts`：

```kotlin
dependencies {
    compileOnly(project(":xlog"))
}
```

如果使用 Groovy，也就是 `build.gradle`，写成：

```groovy
dependencies {
    compileOnly project(':xlog')
}
```

这里的 `:xlog` 是 Flutter 为 xlog 插件加入的 Gradle 项目，不是底层 Maven AAR。
`compileOnly` 让 `device_plugin` 编译 Kotlin 时能找到 xlog 的类；运行时由 Flutter
根据 pubspec 依赖把 xlog 一起构建进 app。较新的 Flutter 也会自动连接原生插件依赖，
这里显式写出，便于看清编译依赖。可参考 Flutter 的
[插件间依赖说明](https://docs.flutter.dev/packages-and-plugins/developing-packages#handling-package-interdependencies)。

不需要复制 xlog 的 Kotlin 文件，不要写死 pub 缓存路径，也不要在 settings 中再手动
include 一份 `:xlog`。构建工具链要满足前面的 Android 要求。
单独构建 `device_plugin/android` 时，没有完整的 Flutter 项目依赖；请通过宿主 app
或这个 plugin 自带的 Flutter example 构建。

第四步，在 plugin 的 Kotlin 文件中导入并调用：

```kotlin
package com.example.device_plugin

import io.flutter.embedding.engine.plugins.FlutterPlugin
import xyz.bczl.xlog.XLog
import xyz.bczl.xlog.XLogInstance

class DevicePlugin : FlutterPlugin {
    private var nativeLog: XLogInstance? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // Application 已经创建了这个命名实例。
        nativeLog = XLog.getLogInstance("native_app")
        nativeLog?.i("DevicePlugin", "Plugin is ready")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // 日志由应用管理，这里只清除当前 plugin 保存的引用。
        nativeLog = null
    }
}
```

如果想写全局日志，直接调用 `XLog.i("DevicePlugin", "Message")`。
命名实例返回 `null` 时，检查 Application 是否在 Flutter 启动前创建了 `native_app`，
以及前缀是否写对。不要让每个 plugin 分别初始化或关闭共用的日志。

前面示例中的 `AppLogs` 是 app 模块里的类。plugin 应通过 `XLog.getLogInstance`
获取实例，或者由应用传入日志回调；不要反过来导入 app 的 `AppLogs`，造成依赖方向错误。

第五步，在 `my_app` 中运行 `flutter pub get`，然后构建应用或同步它的 Android 项目。
如果出现 `Project with path ':xlog' could not be found`，先检查 plugin 的 pubspec
普通依赖，以及宿主是否保留 Flutter 插件加载配置。不要手动修改生成的
`.flutter-plugins-dependencies` 文件。

### 同一个本地 plugin 的 Swift 代码打日志

保留上述 pubspec 依赖，在已有的
`packages/device_plugin/ios/device_plugin.podspec` 配置块中加入：

```ruby
s.dependency 'xlog'
```

然后在这个 plugin 的 Swift 文件中调用：

```swift
import xlog

func logFromPlugin() {
  XLog.info("DevicePlugin", message: "A global log message")
  XLog.instance(namePrefix: "native_app")?.info(
    "DevicePlugin", message: "A named-instance message"
  )
}
```

在 app 中执行 `flutter pub get`，再到 app 的 `ios` 目录执行 `pod install`。
和 Android 一样，由 app 统一初始化。
这里依赖 `xlog`，才能使用当前插件的 Swift 类；如果只依赖 `mars-xlog`，
拿到的是更底层的原生日志库。

<a id="third-party-native-libraries"></a>

## 接入原生第三方库

要共用这些日志文件，第三方库必须调用同一个日志后端。
仅仅初始化 xlog，不会自动接管 `android.util.Log`、`NSLog`、`printf`、
Flutter `print` 或其他库自己的日志系统。

### Android Java／Kotlin 库

如果 SDK 支持日志回调，优先在应用层接入。例如回调类型是 `(String, String) -> Unit`：

```kotlin
val sdkLogSink: (String, String) -> Unit = { tag, message ->
    AppLogs.native.i(tag, message)
}
// 把 sdkLogSink 传给 SDK 自己提供的日志配置方法。
```

这样 SDK 不必知道 Flutter 的存在。如果是另一个 Flutter plugin 想直接导入
`xyz.bczl.xlog.*`，按上面的本地 plugin 步骤配置。

如果 SDK 直接使用 `com.tencent.mars.xlog.*`，可以声明匹配版本的原生 Maven 依赖。
插件使用 `implementation`，其他模块不能假定其编译路径自动包含底层 Java 类。
整个应用统一解析到一份后端版本，并由应用初始化；不要再打包一份 AAR，
也不要在 SDK 内另外打开全局 appender。

### iOS Swift／Objective-C 库

Runner 中的 Swift 使用 `import xlog`。Objective-C 可以导入生成的 Swift 接口：

```objc
#import <xlog/xlog-Swift.h>

[XLog info:@"SDK" message:@"This uses the global instance"];
```

第三方 SDK 支持回调时，注入一个调用 `AppLogs.native?.info(tag, message: message)`
的闭包，即可写入单独的原生日志。生成的 Swift 头文件应在 `.m`／`.mm` 中导入，
不要放进用于构建同一 Swift 模块的 bridging header。

独立 Pod 需要声明自己的依赖，不能因为 Runner 已经引入，就认为它自己的 target
也能直接访问。直接使用底层后端的原生 SDK，可以在 podspec 中添加：

```ruby
s.dependency 'mars-xlog', '1.3.7'
```

CocoaPods 可以将它与 Flutter 插件的依赖解析到同一份后端。
注意名字：Pod 叫 `mars-xlog`，framework／module 叫 `mars`，
Flutter 插件模块叫 `xlog`。如果要直接使用插件的 Swift 封装，则声明 `xlog` Pod
依赖。不要在预编译 SDK 内再静态塞入另一份 Mars。
参见 [CocoaPods 依赖说明](https://guides.cocoapods.org/syntax/podspec.html#dependency)。

闭源 SDK 如果既没有回调，也不支持替换日志后端，就需要提供方增加接入能力；
本插件不能自动重定向它的输出。

<a id="jni-and-c-integration"></a>

## 接入 JNI 与 C++

C++ 直接调用 Mars，不需要绕到 Dart 或平台通道。先在 Application／AppDelegate
初始化，再允许 SDK／原生线程写日志。JNI 和 SDK 不要再次打开全局 appender。

### Android 编译与链接

AAR 已经包含 `libmarsxlog.so`、`libc++_shared.so`，但查阅的构建没有发布 Prefab。
所以 Flutter／Maven 依赖并不会自动提供 CMake target 或头文件搜索路径。

1. 获取 Gradle 实际解析到的同版本 AAR，解压到构建暂存目录。AAR 就是 ZIP，
   原生库位于 `jni/<abi>/libmarsxlog.so`。
2. 准备匹配版本的头文件：`mars/comm/xlogger/xloggerbase.h`；使用命名实例还需要
   `mars/xlog/xlogger_interface.h` 及它依赖的 `appender.h`。
3. 链接现有动态库，不要把 Mars 源码或另一份静态 xlog 编进自己的 SDK。

在构建 JNI 库的 CMake 项目中加入：

```cmake
# 配置 -DXLOG_AAR_DIR=... 与 -DXLOG_SOURCE_ROOT=...
# AAR_DIR 是 AAR 解压目录；SOURCE_ROOT 是匹配版本的原生源码根目录。
add_library(marsxlog SHARED IMPORTED)
set_target_properties(marsxlog PROPERTIES
    IMPORTED_LOCATION "${XLOG_AAR_DIR}/jni/${ANDROID_ABI}/libmarsxlog.so")

add_library(app_native SHARED native_logging.cpp)
target_include_directories(app_native PRIVATE
    "${XLOG_SOURCE_ROOT}/mars/comm/xlogger"
    "${XLOG_SOURCE_ROOT}/mars/xlog")
target_link_libraries(app_native PRIVATE marsxlog)
```

如果已经有 `app_native`，就在现有 target 上追加配置。
在模块 Gradle 中配置 `externalNativeBuild.cmake`，使用 `c++_shared`，
并覆盖应用支持的 ABI。`XLog.init` 完成后，再用 `System.loadLibrary("app_native")`
加载自己的 JNI 库。

AGP 可能同时收集 CMake 导入的库和 AAR 中的库。如果报 `libmarsxlog.so` 重复，
先确认两份是相同二进制，再在应用中选择保留一份：

```kotlin
android {
    packaging {
        jniLibs.pickFirsts += "**/libmarsxlog.so"
    }
}
```

不要用 `pickFirst` 掩盖两个不同版本；C++ runtime 也应统一到一份兼容版本。
参见 Android [原生链接说明](https://developer.android.com/studio/projects/gradle-external-native-builds)。

### iOS 编译与链接

Runner 已经通过 CocoaPods 链接 `mars`。混合 Objective-C／C++ 的文件使用 `.mm`；
纯 `.cpp` 也可以调用，只要所在 target 配好了 Mars framework／头文件路径与 C++ 链接。
独立 Pod 自己声明 `mars-xlog`，在 `source_files` 中加入 `.mm`／`.cpp`，
并按 target 要求链接 C++ 标准库，不要重复嵌入静态 XCFramework。

发行头文件路径为 `<mars/xlog/xloggerbase.h>` 和 `<mars/xlog/xlogger_interface.h>`。
纯 C++ 使用这些头文件，不要导入插件的 Swift 生成头文件。

### C++ 写入全局实例

下面的辅助函数适用于前面的 Android 搜索路径和 iOS framework 目录结构。
消息按普通字符串处理，`%` 不会触发格式化：

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

// 初始化后调用：WriteSdkLog(kLevelInfo, "NativeSdk", "progress=100%");
```

在本文的双实例配置中，它写入的是全局的 `flutter_app`。
如果 SDK 回调提供源码位置，可以再填入 filename／function／line 字段。

### C++ 写入原生命名实例

要写到独立的 `native_app`，通过原生注册表查找启动时已创建的实例：

```cpp
#include <cstdint>
#if defined(__APPLE__)
#include <mars/xlog/xlogger_interface.h>
#else
#include "xlogger_interface.h"
#endif

// 复用上面的 MakeLogInfo。
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

这里借用实例，不负责创建或释放。关闭前先停止写入，不能在这些调用期间并发关闭，
也不能在关闭后继续使用指针。头文件、C++ runtime 和二进制版本需要匹配，
C++ API 不是跨版本稳定的 ABI。本次查阅的 Android 导出表包含这些命名实例符号，
更换原生构建时要重新核对导出。

SDK 提供 C 日志回调时，可以接到上述任一辅助函数。
如果你另外为 Dart 增加 iOS C 桥接，需要保证符号在最终二进制中被保留并导出，
参见 [Flutter 原生链接说明](https://docs.flutter.dev/platform-integration/legacy-ffi-plugin#dynamic-versus-static-linking)。
上面这些 C++ 调用本身不需要新增 Dart 桥接。

<a id="lifecycle-and-troubleshooting"></a>

## 生命周期与常见问题

- 只初始化一次，并且尽早初始化。之后再启动会打日志的 SDK。Hot restart 不会
  重启 Application／AppDelegate，不要因此在 Dart 重新打开全局日志。
- 应用统一管理关闭。SDK 不要关闭共用的全局实例；Dart 关闭也会影响原生写入。
  关闭命名实例前先停止写入，不要假定两端的全局 flush／close 对所有实例的行为完全相同。
- 同步刷盘不要放在主线程。原生 `flushSync` 会阻塞。当前 Pigeon handler 使用
  默认线程，Dart 返回 `Future` 不代表 `flush(sync: true)` 自动到了原生后台。
  日常使用异步 flush；确实需要同步时，在原生后台任务中协调执行。
- 实例可以与进程同寿命，无需专门添加退出 close／flush 钩子。下次启动时，使用相同
  目录和前缀重新初始化即可；收集上传日志前按需 flush。Android `Application.onTerminate()`
  和 iOS 终止回调都不适合作为保存最后日志的保证，进程被强制结束时仍可能丢失缓冲数据。
- 多进程使用不同日志目标。Android 每个应用进程都会执行 Application；独立进程
  使用不同目录／前缀。同一进程内的 isolate 或 Flutter engine 仍共用原生全局后端。
- Android 动态级别：`XLogManager.setLevel` 转给 `Log.setLevel`，查阅的原生源码中
  该 Java 方法没有更新 C++ 级别。Dart 可以使用 `XLogger.level = ...` 设置全局 FFI
  阈值，原生可用 `xlogger_SetLevel`。依赖 Kotlin setter 前请核对实际后端版本。
- 没有日志文件：检查初始化顺序、目录权限、过滤级别和异步缓冲是否已刷出。
  控制台有输出不代表文件一定写成功。初始化可能失败，也可能忽略重复打开，不能用它更新配置。
- Android 构建失败：检查宿主 JitPack、ABI、CMake 导入和后端版本是否统一。
  如果 release 混淆破坏 JNI 查找，在应用 R8 配置中保留后端类及配置字段，例如
  `-keep class com.tencent.mars.xlog.** { *; }`。
- iOS 构建失败：使用 Pods workspace 和正确的 XCFramework 切片。Intel 模拟器
  需要另外构建原生库。FFI 查不到符号时，检查 release 二进制导出与自定义链接裁剪设置。

<a id="development"></a>

## 开发

在插件目录运行常规检查：

```sh
flutter pub get
flutter analyze
flutter test
```

只有修改对应 API 时才需要重新生成代码：

```sh
dart run pigeon --input pigeon/xlog_config.dart
dart run ffigen --config ffigen.yaml
```

`ffigen.yaml` 包含本机 LLVM 路径和 Windows 头文件 shim，换机器后需要调整，并核对目标
ABI。插件声明的原生依赖是 Android `com.github.arcticfox1919:xlog:1.3.7` 和 iOS
`mars-xlog` `1.3.7`。分析后端行为时使用匹配的源码和二进制；旧二进制可能在 FFI 首次解析
所需符号时失败，当前实现不兼容 1.3.6 的旧 writer 接口。

Android 使用 Gradle 远程依赖，无需配置本地 AAR 加载。在 `example/` 目录验证集成：

```sh
flutter pub get
flutter build apk --debug
```

iOS 的 CocoaPods／XCFramework 构建与链接验证需要在 macOS 上完成。
启动接入见[示例应用](example)；后端源码、构建脚本、密钥工具和解码器见
[原生项目](https://github.com/arcticfox1919/xlog)。Android 最终打包还需满足
[16 KB 内存页要求](https://developer.android.com/guide/practices/page-sizes)。

### 可选的原生桥接测试与性能基准

这些脚本都放在 `test/` 下。主机 FFI 测试需要 C++ 编译器和匹配的原生 xlog 源码；
没有生成主机测试库时，对应测试会跳过。先构建测试库，再运行测试：

```sh
dart run test/native/build_writer_test_library.dart --compiler clang++ --mars-root /path/to/xlog
flutter test
```

辅助脚本会编译生产代码中的 C 适配层，并使用测试接收端代替真实文件写入。
覆盖实例路由、只查找一次实例、级别过滤、有界缓冲复用、超限临时分配、释放及同步回调重入。

使用同一个接收端测量 Dart 到原生的桥接成本：

```sh
dart compile exe test/benchmark/benchmark_writer.dart -o .dart_tool/native_writer/benchmark
.dart_tool/native_writer/benchmark 200000
.dart_tool/native_writer/benchmark 200000 --vary-tags
```

Windows 下将输出文件及运行命令改为 `benchmark.exe`。这是主机 AOT 基准，不包含真实
Android／iOS 磁盘写入、压缩或加密，不能直接当作手机端完整日志吞吐量。

Java 配置和生命周期契约检查使用 JDK 8 或 17，以支持 Java 7 source／target：

```sh
dart run test/java/test_java_instances.dart --mars-root /path/to/xlog --javac /jdk8/bin/javac --java /jdk8/bin/java
```

脚本会用临时 Android／JNI 主机桩验证两份原生 SDK 源码，覆盖配置透传、重复前缀、
创建失败、旧接口默认值、第三方后端及并发生命周期操作，不执行 Android 加密或文件 I/O。

Flutter 构建和这些开发脚本都不依赖 Python。`tool/decode_xlog.py` 是独立命令行解码工具，
不属于插件运行时。图形化工具见[解码](#解码)。

## 许可证

本 Flutter 插件使用 [MIT 许可证](LICENSE)。Mars xlog 和其中的第三方组件保留各自的许可证。
