// FILE: lib/feature/writing/writing_page.dart
import 'package:flutter/material.dart';
import 'editor_page.dart';
import 'diff_page.dart';

class WritingPage extends StatefulWidget {
  const WritingPage({super.key});

  @override
  State<WritingPage> createState() => _WritingPageState();
}

class _WritingPageState extends State<WritingPage> {
  int _index = 0;

  // 초안 전달을 위해 상태 공유(간단 전역)
  String _draftToCompareOriginal = '';
  String _draftToCompareRevised = '';

  @override
  Widget build(BuildContext context) {
    final pages = [
      EditorPage(
        onSendToDiff: (original, revised) {
          setState(() {
            _draftToCompareOriginal = original;
            _draftToCompareRevised = revised;
            _index = 1; // Diff 탭으로 전환
          });
        },
      ),
      DiffPage(
        initialOriginal: _draftToCompareOriginal,
        initialRevised: _draftToCompareRevised,
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Writing')),
      body: SafeArea(child: pages[_index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.edit_note_outlined),
            selectedIcon: Icon(Icons.edit_note),
            label: 'Writing',
          ),
          NavigationDestination(
            icon: Icon(Icons.compare_arrows_outlined),
            selectedIcon: Icon(Icons.compare_arrows),
            label: 'Diff',
          ),
        ],
      ),
    );
  }
}



