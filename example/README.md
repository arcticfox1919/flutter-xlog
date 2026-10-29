# XLog example and benchmarks

English | [简体中文](README.zh-CN.md)

The default logger, `xlog_example`, and a named business instance, `xlog_other`,
are created during Android / iOS startup. Dart only binds existing instances.
Each instance has buttons for a sample entry and 1,000- or 10,000-entry benchmarks.
The business instance also demonstrates flushing and listing today's log files.

Both instances use INFO, asynchronous mode, console mirroring disabled, an 8 MiB
file splitting threshold, and seven-day retention.
**The default logger and all named instances must have separate log and cache
directories.** Native cleanup scans the entire directory; different prefixes do
not isolate retention policies. The example uses separate subdirectories under
a common parent.

## Run

Run on a physical Android or iOS device. For performance comparisons, use
`flutter run --profile` or `flutter run --release`. Debug builds and emulators
are useful for functional checks but do not represent device release performance.

The example uses native xlog 1.4.0 on Android and iOS. Use matching native packages
that contain the current configuration fields and writer C API. Update the iOS
lockfile with `pod update mars-xlog xlog` and build iOS on macOS.

## Timing methodology

- Each message body is exactly **256 UTF-8 bytes**, containing a request ID,
  route, elapsed time, trace, and Chinese text. This excludes the tag, native
  timestamp, and log header; compressed file size differs from message size.
- Each run generates messages, warms up with 200 entries, flushes, then measures
  1,000 or 10,000 submissions. Message generation, warmup, isolate startup, and
  flushing are excluded from submission time.
- Submission time includes encoding, FFI, and native submission through the real
  public writer. Results also show average time per entry and submission throughput.
  The final synchronous flush is measured separately, including platform-channel
  and native flush overhead.
- A worker isolate binds its own writer. The UI runs one benchmark at a time to
  avoid interference from concurrent buttons. Rejected writes or filtered INFO
  logs produce an error rather than a successful result.
- Successful asynchronous submission does not mean durability. Synchronous
  flushing does not guarantee survival of a power failure either. These tests
  compare application call costs in the same mode, rather than raw disk bandwidth
  or maximum durable throughput.
- Each run also produces 200 warmup entries. Logs accumulate, so repeated runs
  may trigger file splitting. Repeat on the same device in the same build mode
  and retain variability. The UI keeps the latest eight results and can copy
  them as tabular text.

## Verify

Run `flutter analyze` and `flutter test` from `example/`. Tests cover message
byte counts, warmup and flush order, rejected writes, all four instance/count
buttons, prevention of overlapping runs, error feedback, and the business
instance's file demo. Host tests use an injectable client; their simulated data
is not presented as device performance results.

Once native dependencies are ready, run
`flutter test integration_test/benchmark_test.dart -d <device-id>` on a device to
verify real FFI writes, worker-isolate flushing, and named-instance file queries.
