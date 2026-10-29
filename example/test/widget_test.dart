import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xlog_example/benchmark.dart';
import 'package:xlog_example/logging_demo.dart';
import 'package:xlog_example/main.dart';

class FakeClient implements ExampleLogClient {
  final calls = <(LogTarget, int)>[];
  final samples = <LogTarget>[];
  Completer<BenchmarkResult>? pending;
  bool fail = false;
  bool disposed = false;

  @override
  Future<void> initialize() async {}

  @override
  Future<BenchmarkResult> benchmark(LogTarget target, int count) async {
    calls.add((target, count));
    if (fail) throw StateError('写入失败');
    if (pending != null) return pending!.future;
    return result(target, count);
  }

  BenchmarkResult result(LogTarget target, int count) => BenchmarkResult(
        target: target,
        count: count,
        writeTime: const Duration(milliseconds: 12),
        flushTime: const Duration(milliseconds: 3),
      );

  @override
  void writeSample(LogTarget target) => samples.add(target);

  @override
  Future<List<String>> businessLogFiles() async =>
      ['/log-other/xlog_other.xlog'];

  @override
  void dispose() => disposed = true;
}

void main() {
  Future<void> start(WidgetTester tester, FakeClient client) async {
    tester.view.physicalSize = const Size(1100, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MyApp(client: client));
    await tester.pumpAndSettle();
  }

  testWidgets('both instances expose both counts and show measured results',
      (tester) async {
    final client = FakeClient();
    await start(tester, client);
    for (final target in LogTarget.values) {
      for (final count in benchmarkCounts) {
        await tester
            .tap(find.byKey(ValueKey('benchmark-${target.name}-$count')));
        await tester.pumpAndSettle();
        expect(client.calls.last, (target, count));
        final text =
            tester.widget<Text>(find.byKey(const ValueKey('latest-result')));
        expect(text.data, contains(target.label));
        expect(text.data, contains(count == 1000 ? '1,000' : '10,000'));
      }
    }
    expect(find.text('12.00 ms'), findsOneWidget);
    expect(find.text('3.00 ms'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('running a batch disables all producers and prevents overlap',
      (tester) async {
    final client = FakeClient()..pending = Completer<BenchmarkResult>();
    await start(tester, client);
    await tester.tap(find.byKey(const ValueKey('benchmark-business-10000')));
    await tester.pump();
    expect(find.byKey(const ValueKey('busy')), findsOneWidget);
    for (final target in LogTarget.values) {
      final button = tester.widget<OutlinedButton>(
          find.byKey(ValueKey('sample-${target.name}')));
      expect(button.onPressed, isNull);
      for (final count in benchmarkCounts) {
        final benchmark = tester.widget<FilledButton>(
            find.byKey(ValueKey('benchmark-${target.name}-$count')));
        expect(benchmark.onPressed, isNull);
      }
    }
    expect(client.calls, hasLength(1));
    client.pending!.complete(client.result(LogTarget.business, 10000));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('busy')), findsNothing);
  });

  testWidgets('child sample and file listing use the child instance',
      (tester) async {
    final client = FakeClient();
    await start(tester, client);
    await tester.tap(find.byKey(const ValueKey('sample-business')));
    await tester.pump();
    expect(client.samples, [LogTarget.business]);
    await tester.tap(find.byKey(const ValueKey('business-files')));
    // The operation remains busy until the modal closes; its progress
    // indicator intentionally keeps animating behind the dialog.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('/log-other/xlog_other.xlog'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    expect(client.disposed, isTrue);
  });

  testWidgets('failed submission shows the error and no successful result',
      (tester) async {
    final client = FakeClient()..fail = true;
    await start(tester, client);
    await tester.tap(find.byKey(const ValueKey('benchmark-application-1000')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('error')), findsOneWidget);
    expect(find.byKey(const ValueKey('latest-result')), findsNothing);
    expect(find.byKey(const ValueKey('busy')), findsNothing);
  });

  testWidgets('phone layout can reach the child benchmark and results',
      (tester) async {
    final client = FakeClient();
    await start(tester, client);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('benchmark-business-10000'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('latest-result')));
    expect(client.calls.single, (LogTarget.business, 10000));
    expect(tester.takeException(), isNull);
  });
}
