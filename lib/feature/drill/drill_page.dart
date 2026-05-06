// FILE: lib/feature/drill/drill_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';

import '../../core/network/server_config.dart';

class DrillItem {
  final int id;
  final String prompt;
  final String pattern;
  final String example;
  final String answer;
  final List<String> tags;

  DrillItem({
    required this.id,
    required this.prompt,
    required this.pattern,
    required this.example,
    required this.answer,
    required this.tags,
  });

  factory DrillItem.fromJson(Map<String, dynamic> j) => DrillItem(
        id: j['id'] as int,
        prompt: j['prompt'] as String,
        pattern: j['pattern'] as String,
        example: j['example'] as String,
        answer: j['answer'] as String,
        tags: (j['tags'] as List).map((e) => e.toString()).toList(),
      );
}

class GradeResult {
  final int itemId;
  final int score;
  final String verdict;
  final String feedback;
  final String expected;

  GradeResult({
    required this.itemId,
    required this.score,
    required this.verdict,
    required this.feedback,
    required this.expected,
  });

  factory GradeResult.fromJson(Map<String, dynamic> j) => GradeResult(
        itemId: j['item_id'] as int,
        score: j['score'] as int,
        verdict: j['verdict'] as String,
        feedback: j['feedback'] as String,
        expected: j['expected'] as String,
      );
}

class DrillPage extends StatefulWidget {
  const DrillPage({super.key});

  @override
  State<DrillPage> createState() => _DrillPageState();
}

class _DrillPageState extends State<DrillPage> {
  List<DrillItem> _items = <DrillItem>[];
  int _idx = 0;
  final TextEditingController _answerCtrl = TextEditingController();
  GradeResult? _lastResult;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchItems();
  }

  @override
  void dispose() {
    _answerCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchItems() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dio = Dio(BaseOptions(baseUrl: serverBaseUrl));
      final res = await dio.get('/drill/items');
      final data = (res.data['items'] as List)
          .map((e) => DrillItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      setState(() {
        _items = data;
        _idx = 0;
      });
    } catch (e) {
      setState(() => _error = '문항을 불러오지 못했습니다. 서버를 확인하세요.');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _grade() async {
    if (_items.isEmpty) return;
    final item = _items[_idx];
    final ans = _answerCtrl.text.trim();
    if (ans.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('답안을 입력하세요')));
      return;
    }
    setState(() {
      _loading = true;
      _lastResult = null;
    });
    try {
      final dio = Dio(BaseOptions(baseUrl: serverBaseUrl));
      final res = await dio.post('/drill/grade', data: <String, dynamic>{
        'item_id': item.id,
        'user_answer': ans,
      });
      setState(() {
        _lastResult =
            GradeResult.fromJson(Map<String, dynamic>.from(res.data as Map));
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('채점 실패: 서버 확인')));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _retry() {
    _answerCtrl.clear();
    setState(() => _lastResult = null);
  }

  void _next() {
    if (_items.isEmpty) return;
    setState(() {
      _idx = (_idx + 1) % _items.length;
      _answerCtrl.clear();
      _lastResult = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(_error!),
            const SizedBox(height: 8),
            FilledButton(onPressed: _fetchItems, child: const Text('다시 시도')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: FilledButton(onPressed: _fetchItems, child: const Text('문항 불러오기')),
      );
    }

    final item = _items[_idx];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: <Widget>[
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Wrap(
                    spacing: 8,
                    children: item.tags.map((t) => Chip(label: Text(t))).toList(),
                  ),
                  const SizedBox(height: 8),
                  Text(item.prompt, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      const Icon(Icons.tips_and_updates_outlined),
                      const SizedBox(width: 6),
                      Text('힌트: ${item.pattern}'),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () {
                          showDialog<void>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('예시'),
                              content: Text(item.example),
                              actions: <Widget>[
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('닫기'),
                                ),
                              ],
                            ),
                          );
                        },
                        icon: const Icon(Icons.visibility_outlined),
                        label: const Text('예시'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _answerCtrl,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '영어로 문장을 작성하세요',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      FilledButton.icon(
                        onPressed: _loading ? null : _grade,
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('채점'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _lastResult == null ? null : _retry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('재도전'),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _next,
                        icon: const Icon(Icons.skip_next),
                        label: const Text('다음'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_lastResult != null)
            _ResultCard(
              result: _lastResult!,
              onCopyExpected: () async {
                await Clipboard.setData(ClipboardData(text: _lastResult!.expected));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('정답 예시가 클립보드에 복사되었습니다')),
                  );
                }
              },
            ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final GradeResult result;
  final VoidCallback onCopyExpected;

  const _ResultCard({required this.result, required this.onCopyExpected});

  Color _color() {
    switch (result.verdict) {
      case 'correct':
        return Colors.green;
      case 'partial':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  IconData _icon() {
    switch (result.verdict) {
      case 'correct':
        return Icons.verified;
      case 'partial':
        return Icons.pending_outlined;
      default:
        return Icons.close;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(children: <Widget>[
              Icon(_icon(), color: _color()),
              const SizedBox(width: 8),
              Text(
                'Score: ${result.score} • ${result.verdict.toUpperCase()}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ]),
            const SizedBox(height: 8),
            Text(result.feedback),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                const Text('정답 예시: '),
                Expanded(
                  child: Text(
                    result.expected,
                    style: const TextStyle(fontStyle: FontStyle.italic),
                  ),
                ),
                IconButton(
                  onPressed: onCopyExpected,
                  icon: const Icon(Icons.copy_all_outlined),
                  tooltip: '정답 예시 복사',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}



