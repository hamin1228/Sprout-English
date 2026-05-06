// FILE: lib/feature/paraphrase/paraphrase_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';

import '../../core/network/server_config.dart';

class ParaphrasePage extends StatefulWidget {
  const ParaphrasePage({super.key});

  @override
  State<ParaphrasePage> createState() => _ParaphrasePageState();
}

class _ParaphrasePageState extends State<ParaphrasePage> {
  final TextEditingController _inputCtrl = TextEditingController();
  String _tone = 'formal';
  bool _loading = false;

  String? _result;
  String? _tips;
  String? _error;

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    FocusScope.of(context).unfocus();
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('문장을 입력하세요')));
      return;
    }
    setState(() {
      _loading = true;
      _result = null;
      _error = null;
    });
    try {
      final dio = Dio(BaseOptions(baseUrl: serverBaseUrl));
      final res = await dio.post('/paraphrase', data: <String, dynamic>{
        'text': text,
        'tone': _tone,
      });
      setState(() {
        _result = res.data['result'] as String;
        _tips = (res.data['tips'] ?? '') as String;
      });
    } catch (e) {
      setState(() => _error = '변환 실패: 서버를 확인하세요.');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _copy(String txt) async {
    await Clipboard.setData(ClipboardData(text: txt));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('복사되었습니다')));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: <Widget>[
          TextField(
            controller: _inputCtrl,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '변환할 문장을 입력하세요',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              const Text('톤:'),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _tone,
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: 'formal', child: Text('격식')),
                  DropdownMenuItem(value: 'concise', child: Text('간결')),
                  DropdownMenuItem(value: 'emphasis', child: Text('강조')),
                  DropdownMenuItem(value: 'persuasive', child: Text('설득')),
                ],
                onChanged: (v) => setState(() => _tone = v ?? 'formal'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _loading ? null : _run,
                icon: const Icon(Icons.play_arrow),
                label: const Text('변환'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red)),
          if (_result != null)
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text('원문', style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 6),
                    Text(_inputCtrl.text),
                    const SizedBox(height: 12),
                    Text('변환 결과',
                        style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 6),
                    SelectableText(_result!),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        OutlinedButton.icon(
                          onPressed: () => _copy(_result!),
                          icon: const Icon(Icons.copy_all_outlined),
                          label: const Text('복사'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => _copy(_inputCtrl.text),
                          icon: const Icon(Icons.copy_outlined),
                          label: const Text('원문 복사'),
                        ),
                        const Spacer(),
                        if ((_tips ?? '').isNotEmpty)
                          Tooltip(
                            message: _tips!,
                            child: const Icon(Icons.info_outline),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}



