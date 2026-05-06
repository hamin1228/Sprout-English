// FILE: lib/feature/writing/editor_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'widgets/checklist_tile.dart';

class EditorPage extends StatefulWidget {
  final void Function(String original, String revised) onSendToDiff;
  const EditorPage({super.key, required this.onSendToDiff});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final _originalCtrl = TextEditingController();
  final _revisedCtrl = TextEditingController();

  final _templates = <String, String>{
    'Daily Routine': "Every morning, I ... In the afternoon, I ... In the evening, I ...",
    'Opinion (Pros/Cons)': "I think that ... because ... However, ... Therefore, ...",
    'Problem & Solution': "The problem is ... It affects ... A possible solution is ...",
  };
  String? _selectedTemplate;

  // 체크리스트(간단한 예시)
  final _checks = <String, bool>{
    '서론-본론-결론 구조': false,
    '문장 길이 다양화(짧/중/길)': false,
    '접속사/연결어 사용(However, Therefore...)': false,
    '오탈자/시제 재검토': false,
  };

  static const int wordLimit = 250;

  int _countWords(String text) {
    final words = RegExp(r"[A-Za-z']+")
        .allMatches(text)
        .map((m) => m.group(0))
        .where((w) => (w ?? '').isNotEmpty)
        .length;
    return words;
  }

  @override
  void dispose() {
    _originalCtrl.dispose();
    _revisedCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final words = _countWords(_revisedCtrl.text);
    final over = words > wordLimit;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Writing — Template · Checklist · Limit'),
        actions: [
          IconButton(
            tooltip: '초안 복사',
            onPressed: () async {
              final text = _revisedCtrl.text;
              if (text.isEmpty) return;
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('초안을 클립보드로 복사했습니다.')),
                );
              }
            },
            icon: const Icon(Icons.copy_all),
          ),
          IconButton(
            tooltip: '초안 지우기',
            onPressed: () {
              _revisedCtrl.clear();
              setState(() {});
            },
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          widget.onSendToDiff(_originalCtrl.text, _revisedCtrl.text);
        },
        icon: const Icon(Icons.compare_arrows),
        label: const Text('Diff로 보내기'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 템플릿 셀렉터
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedTemplate,
                  decoration: const InputDecoration(
                    labelText: '템플릿 선택',
                    border: OutlineInputBorder(),
                  ),
                  isExpanded: true,
                  items: _templates.keys
                      .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _selectedTemplate = v);
                  },
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonalIcon(
                onPressed: () {
                  final key = _selectedTemplate;
                  if (key == null) return;
                  final tpl = _templates[key]!;
                  _revisedCtrl.text = (_revisedCtrl.text.isEmpty)
                      ? tpl
                      : "${_revisedCtrl.text.trim()}\n\n$tpl";
                  setState(() {});
                },
                icon: const Icon(Icons.playlist_add),
                label: const Text('삽입'),
              )
            ],
          ),
          const SizedBox(height: 16),
          // 체크리스트 카드
          Card(
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('체크리스트', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  ..._checks.entries.map((e) => ChecklistTile(
                        label: e.key,
                        value: e.value,
                        onChanged: (v) {
                          setState(() => _checks[e.key] = v ?? false);
                        },
                      )),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 원문 입력(선택)
          TextField(
            controller: _originalCtrl,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: '원문(비교용 · 선택)',
              hintText: '교정 전 문장을 붙여넣으면, Diff 화면에서 비교할 수 있어요.',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          // 수정문(주요 편집 영역)
          TextField(
            controller: _revisedCtrl,
            maxLines: 12,
            decoration: InputDecoration(
              labelText: '수정문(최종 초안)',
              hintText: '여기에 템플릿을 기반으로 글을 작성하세요.',
              border: const OutlineInputBorder(),
              helperText: '단어 제한: $wordLimit words',
              suffixIcon: (over)
                  ? const Tooltip(message: '단어수 초과', child: Icon(Icons.warning_amber))
                  : const Icon(Icons.check_circle_outline),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          // 카운터/경고
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('단어수: $words / $wordLimit'),
              if (over)
                Text(
                  '제한 초과! 일부를 줄여 주세요.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }
}



