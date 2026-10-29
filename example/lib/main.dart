import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'benchmark.dart';
import 'logging_demo.dart';

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.client});

  final ExampleLogClient? client;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final ExampleLogClient _client;
  final _results = <BenchmarkResult>[];
  bool _ready = false;
  bool _busy = false;
  String? _error;
  String _activity = '正在连接原生日志实例…';
  bool get _enabled => _ready && !_busy;

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? NativeExampleLogClient();
    _initialize();
  }

  Future<void> _initialize() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _client.initialize();
      if (!mounted) return;
      setState(() {
        _ready = true;
        _activity = '两个实例已就绪 · 控制台输出已关闭';
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _benchmark(LogTarget target, int count) async {
    if (!_enabled) return;
    setState(() {
      _busy = true;
      _error = null;
      _activity = '正在测试 ${target.label} · ${_count(count)} 条…';
    });
    try {
      final result = await _client.benchmark(target, count);
      if (!mounted) return;
      setState(() {
        _results.insert(0, result);
        if (_results.length > 8) _results.removeLast();
        _activity = '${target.label} · ${_count(count)} 条测试完成';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _activity = '测试未完成，请检查错误信息后重试';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _sample(LogTarget target) {
    if (!_enabled) return;
    try {
      _client.writeSample(target);
      setState(() {
        _error = null;
        _activity = '已向${target.label}提交一条示例日志';
      });
    } catch (error) {
      setState(() => _error = '$error');
    }
  }

  Future<void> _files(BuildContext context) async {
    if (!_enabled) return;
    setState(() {
      _busy = true;
      _error = null;
      _activity = '正在刷写并查询子实例文件…';
    });
    try {
      final files = await _client.businessLogFiles();
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('业务子实例 · 今日日志文件'),
          content: SingleChildScrollView(
            child: SelectableText(
                files.isEmpty ? '暂无文件，请先写入日志。' : files.join('\n\n')),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
      if (mounted) setState(() => _activity = '已查询子实例的独立日志目录');
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyResults() async {
    final rows = [
      'instance\tcount\tmessage_bytes\twrite_ms\tus_per_log\tlogs_per_second\tflush_ms',
      for (final r in _results)
        '${r.target.prefix}\t${r.count}\t$benchmarkMessageBytes\t'
            '${r.writeMilliseconds.toStringAsFixed(3)}\t'
            '${r.microsecondsPerLog.toStringAsFixed(3)}\t'
            '${r.logsPerSecond.toStringAsFixed(0)}\t'
            '${r.flushMilliseconds.toStringAsFixed(3)}',
    ];
    try {
      await Clipboard.setData(ClipboardData(text: rows.join('\n')));
      if (mounted) setState(() => _activity = '已复制结果，可粘贴到表格');
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  void dispose() {
    _client.dispose();
    super.dispose();
  }

  static String _count(int count) => count == 1000 ? '1,000' : '10,000';

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff185b9d)),
      scaffoldBackgroundColor: const Color(0xfff3f6fa),
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Builder(builder: (context) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('XLog 性能实验室'),
            actions: const [
              Padding(
                padding: EdgeInsets.only(right: 16),
                child: Chip(
                    label: Text(kReleaseMode
                        ? 'RELEASE'
                        : kProfileMode
                            ? 'PROFILE'
                            : 'DEBUG')),
              ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text('让日志性能，看得见。', style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  const Text('1,000 / 10,000 条 · 每条正文 256 字节 · 默认实例与子实例独立测试'),
                  const SizedBox(height: 20),
                  LayoutBuilder(builder: (context, constraints) {
                    final cards = [
                      for (final target in LogTarget.values)
                        _instanceCard(context, target)
                    ];
                    if (constraints.maxWidth >= 680) {
                      return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: cards[0]),
                            const SizedBox(width: 12),
                            Expanded(child: cards[1]),
                          ]);
                    }
                    return Column(children: [
                      cards[0],
                      const SizedBox(height: 12),
                      cards[1]
                    ]);
                  }),
                  const SizedBox(height: 16),
                  if (_busy)
                    const LinearProgressIndicator(key: ValueKey('busy')),
                  const SizedBox(height: 8),
                  Text(_activity, key: const ValueKey('activity')),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    SelectableText(_error!,
                        key: const ValueKey('error'),
                        style: TextStyle(color: theme.colorScheme.error)),
                    if (!_ready)
                      Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                              onPressed: _busy ? null : _initialize,
                              child: const Text('重新连接'))),
                  ],
                  const SizedBox(height: 20),
                  _resultsCard(context),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('测量口径', style: theme.textTheme.titleLarge),
                            const SizedBox(height: 12),
                            const Text(
                                '• 每条正文为 256 字节 UTF-8 请求日志，含变化的请求编号与中文；不含原生时间戳和日志头。\n'
                                '• INFO / 异步模式 / 关闭控制台；每轮预热 200 条，数据生成、预热和 isolate 启动不计入提交耗时。\n'
                                '• 提交耗时包含 Dart 编码、FFI 和原生提交；另计同步刷写耗时，包含平台通道开销。\n'
                                '• 异步提交不等于持久化；刷写到文件也不代表断电不丢失。批量测试在工作 isolate 执行。\n'
                                '• 默认实例与子实例使用独立的日志和缓存目录；不同前缀不能替代目录隔离。'),
                            const SizedBox(height: 12),
                            Text(
                                kDebugMode
                                    ? '当前为 Debug：适合验证功能。性能比较请在同一真机使用 Profile 或 Release，多轮测量。'
                                    : '建议在同一真机、相同构建模式下多轮测量，观察波动。',
                                style: TextStyle(
                                    color: theme.colorScheme.primary)),
                          ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _instanceCard(BuildContext context, LogTarget target) {
    final isBusiness = target == LogTarget.business;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(isBusiness
                ? Icons.account_tree_outlined
                : Icons.description_outlined),
            const SizedBox(width: 10),
            Text(target.label, style: Theme.of(context).textTheme.titleLarge),
          ]),
          const SizedBox(height: 8),
          Text(target.prefix, style: const TextStyle(fontFamily: 'monospace')),
          const SizedBox(height: 8),
          Text(isBusiness
              ? '演示业务隔离：独立写入、刷写和文件查询。'
              : '演示应用日志：复用默认 writer，通过 tag 区分来源。'),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final count in benchmarkCounts)
              FilledButton.tonal(
                key: ValueKey('benchmark-${target.name}-$count'),
                onPressed: _enabled ? () => _benchmark(target, count) : null,
                child: Text('测试 ${_count(count)} 条'),
              ),
            OutlinedButton(
              key: ValueKey('sample-${target.name}'),
              onPressed: _enabled ? () => _sample(target) : null,
              child: const Text('写入示例'),
            ),
            if (isBusiness)
              TextButton.icon(
                key: const ValueKey('business-files'),
                onPressed: _enabled ? () => _files(context) : null,
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('查看今日日志文件'),
              ),
          ]),
        ]),
      ),
    );
  }

  Widget _resultsCard(BuildContext context) {
    final latest = _results.isEmpty ? null : _results.first;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('测试结果', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          if (latest == null)
            const Text('点击任一测试按钮，查看实测耗时。每次串行执行一组测试。')
          else ...[
            Text('${latest.target.label} · ${_count(latest.count)} 条',
                key: const ValueKey('latest-result')),
            const SizedBox(height: 16),
            Wrap(spacing: 28, runSpacing: 16, children: [
              _metric(
                  '提交耗时', '${latest.writeMilliseconds.toStringAsFixed(2)} ms'),
              _metric(
                  '平均每条', '${latest.microsecondsPerLog.toStringAsFixed(2)} μs'),
              _metric(
                  '提交吞吐量', '${latest.logsPerSecond.toStringAsFixed(0)} 条/s'),
              _metric(
                  '同步刷写', '${latest.flushMilliseconds.toStringAsFixed(2)} ms'),
            ]),
            const SizedBox(height: 16),
            const Text('最近 8 次 · 最新在前'),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('实例')),
                  DataColumn(label: Text('条数'), numeric: true),
                  DataColumn(label: Text('提交 ms'), numeric: true),
                  DataColumn(label: Text('刷写 ms'), numeric: true),
                ],
                rows: [
                  for (final r in _results)
                    DataRow(cells: [
                      DataCell(Text(r.target.label)),
                      DataCell(Text(_count(r.count))),
                      DataCell(Text(r.writeMilliseconds.toStringAsFixed(2))),
                      DataCell(Text(r.flushMilliseconds.toStringAsFixed(2))),
                    ])
                ],
              ),
            ),
            Wrap(spacing: 12, children: [
              TextButton.icon(
                  onPressed: _busy ? null : _copyResults,
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('复制结果')),
              TextButton(
                  onPressed: _busy ? null : () => setState(_results.clear),
                  child: const Text('清空结果')),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _metric(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: 4),
          Text(value,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
        ],
      );
}
