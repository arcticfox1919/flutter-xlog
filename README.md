# xlog

`xlog` is a Flutter plugin for Tencent Mars xlog.

It is intended to expose the native C++ xlog logging library to Flutter through `dart:ffi`, so Dart code can write logs through the same high-performance native logging pipeline used by Mars xlog. The native logger does the heavy work in C++, avoiding method-channel logging overhead on hot log paths.

## Features

- Tencent Mars xlog based native logging.
- `dart:ffi` access to the C++ logging library.
- Android 16 KB page size support.
- Android AAR integration for `mars-xlog`.
- iOS XCFramework integration for `mars-xlog`.
- Native Kotlin and Swift facades for hybrid applications.
- Designed for low-overhead logging in Flutter apps.
- Compatible with Dart `>=3.3.0 <4.0.0` and Flutter `>=3.0.0`.

## Android

The Android side is designed to depend on the `mars-xlog` AAR built from the native xlog project. That AAR includes 16 KB page size linker support for modern Android devices.

Expected native ABIs:

- `arm64-v8a`
- `armeabi-v7a`
- `x86_64`

The `x86_64` ABI is included for Android emulators.

## iOS

The iOS plugin depends on the `mars-xlog` CocoaPod and exposes a public Swift/
Objective-C facade. A host application using the Flutter CocoaPods integration
does not need to declare `mars-xlog` again.

Expected XCFramework slices:

- `iphoneos` arm64
- `iphonesimulator` arm64

Hybrid applications can initialize xlog before starting Flutter:

```swift
import xlog

let configuration = XLogConfiguration(
  logDirectory: logDirectory,
  namePrefix: "app"
)
configuration.cacheDirectory = cacheDirectory
configuration.level = .debug

XLog.initialize(configuration: configuration)
XLog.info("AppDelegate", message: "xlog initialized")
```

Flutter's `XLogManager` uses this same native facade, so native and Dart code
share the global appender and log instances.


## Development

Install dependencies:

```sh
flutter pub get
```

Run analyzer:

```sh
flutter analyze
```

Run tests:

```sh
flutter test
```

## License

This plugin repository is released under the MIT License. Tencent Mars xlog keeps its upstream license.
