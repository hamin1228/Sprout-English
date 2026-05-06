// FILE: lib/feature/writing/diff_page.dart
import 'package:flutter/material.dart';
import 'utils/diff_utils.dart';

class DiffPage extends StatefulWidget {
  final String initialOriginal;
  final String initialRevised;

  const DiffPage({
    super.key,
    this.initialOriginal = '',
    this.initialRevised = '',
  });

  @override
  State<DiffPage> createState() => _DiffPageState();
}

class _DiffPageState extends State<DiffPage> {
  final _origCtrl = TextEditingController();
  final _revCtrl = TextEditingController();

  bool _preserveSpaces = true;
  DiffResult? _result;

  @override
  void initState() {
    super.initState();
    _origCtrl.text = widget.initialOriginal;
    _revCtrl.text = widget.initialRevised;
  }

  @override
  void dispose() {
    _origCtrl.dispose();
    _revCtrl.dispose();
    super.dispose();
  }

  void _compare() {
    final r = DiffEngine.compare(
      original: _origCtrl.text,
      revised: _revCtrl.text,
      preserveSpaces: _preserveSpaces,
    );
    setState(() => _result = r);
  }

  @override
  Widget build(BuildContext context) {
    final stats = _result?.statsString() ?? '아직 비교하지 않았습니다.';
    final spans = _result?.toTextSpan(context) ??
        const TextSpan(text: '상단의 "비교하기"를 눌러 결과를 확인하세요.');

    return Scaffold(
      appBar: AppBar(title: const Text('Diff — 원문 vs 수정문')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('공백/줄바꿈 보존'),
                    value: _preserveSpaces,
                    onChanged: (v) => setState(() => _preserveSpaces = v),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _compare,
                  icon: const Icon(Icons.playlist_add_check),
                  label: const Text('비교하기'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _origCtrl,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: '원문',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _revCtrl,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: '수정문',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('결과 미리보기', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        SelectableText.rich(spans),
                        const SizedBox(height: 12),
                        Text(
                          stats,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ],
      ),
    );
  }
}



