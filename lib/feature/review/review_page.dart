// FILE: lib/feature/review/review_page.dart
import 'dart:math';
import 'package:flutter/material.dart';

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  final List<String> _allTags = const [
    '문법',
    '발음',
    '단어',
    '표현',
    '리스닝',
  ];

  final List<ReviewCardModel> _allCards = [
    ReviewCardModel(
      id: '1',
      question: 'I have **many homeworks** to do.',
      correctExpression: 'I have **a lot of homework** to do.',
      explanation: 'homework는 셀 수 없는 명사라서 many, -s를 붙이지 않습니다.',
      example: 'I have a lot of homework to do this weekend.',
      tags: const ['문법', '표현'],
      nextDue: DateTime.now(),
      lastReviewed: DateTime.now().subtract(const Duration(days: 1)),
      wrongCount: 3,
    ),
    ReviewCardModel(
      id: '2',
      question: '발음: **comfortable** 을 /컴포터블/로 읽음',
      correctExpression: '발음: /ˈkʌm.fər.tə.bəl/ (컴퍼터블)',
      explanation: '영어에서는 첫 음절에 강세가 옵니다. com-fort-able (컴-퍼-터블).',
      example: 'This sofa is really comfortable.',
      tags: const ['발음'],
      nextDue: DateTime.now(),
      lastReviewed: DateTime.now().subtract(const Duration(days: 2)),
      wrongCount: 2,
    ),
    ReviewCardModel(
      id: '3',
      question: 'He **don\'t** like coffee.',
      correctExpression: 'He **doesn\'t** like coffee.',
      explanation: '3인칭 단수 주어(he, she, it)에는 does/doesn\'t를 사용합니다.',
      example: 'He doesn\'t like coffee at all.',
      tags: const ['문법'],
      nextDue: DateTime.now().add(const Duration(hours: 6)),
      lastReviewed: DateTime.now().subtract(const Duration(days: 3)),
      wrongCount: 1,
    ),
    ReviewCardModel(
      id: '4',
      question: '"How are you?"에 항상 "I\'m fine, thank you."만 대답함',
      correctExpression: '자연스러운 대답 예: "I\'m good. How about you?"',
      explanation: '교과서 표현보다 실제 회화에서 자주 쓰는 패턴을 익혀두면 좋아요.',
      example: 'A: How are you?\nB: I\'m good. How about you?',
      tags: const ['표현', '리스닝'],
      nextDue: DateTime.now(),
      lastReviewed: DateTime.now().subtract(const Duration(days: 4)),
      wrongCount: 4,
    ),
  ];

  final List<TodaysExpression> _todaysCandidates = const [
    TodaysExpression(
      phrase: 'I\'m not sure, but…',
      meaning: '정확하진 않지만, ~인 것 같아요',
      example: 'I\'m not sure, but I think the meeting starts at 3.',
      tip: '모를 때 바로 "I don\'t know" 대신 완곡하게 돌려 말할 수 있는 표현.',
    ),
    TodaysExpression(
      phrase: 'It depends.',
      meaning: '상황에 따라 달라요.',
      example: 'It depends on the weather.',
      tip: '질문에 단정적으로 답하기 애매할 때 쓸 수 있는 만능 표현.',
    ),
    TodaysExpression(
      phrase: 'I\'ll give it a try.',
      meaning: '한번 해 볼게요.',
      example: 'I\'ve never made this dish, but I\'ll give it a try.',
      tip: '도전 의지를 보여줄 때 자연스럽게 쓰이는 표현.',
    ),
  ];

  Set<String> _selectedTags = {};
  late TodaysExpression _currentExpression;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _currentExpression =
        _todaysCandidates[_random.nextInt(_todaysCandidates.length)];
  }

  void _toggleTag(String tag) {
    setState(() {
      if (_selectedTags.contains(tag)) {
        _selectedTags.remove(tag);
      } else {
        _selectedTags.add(tag);
      }
    });
  }

  void _shuffleExpression() {
    setState(() {
      _currentExpression =
          _todaysCandidates[_random.nextInt(_todaysCandidates.length)];
    });
  }

  void _updateSrs(ReviewCardModel card, SrsGrade grade) {
    setState(() {
      card.applyGrade(grade);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          switch (grade) {
            SrsGrade.again => '이 카드를 곧 다시 복습할게요. (Again)',
            SrsGrade.hard => '조금 어려웠네요. (Hard)',
            SrsGrade.good => '좋아요! 적당한 난이도예요. (Good)',
            SrsGrade.easy => '아주 쉽죠? 다음 복습 간격을 늘립니다. (Easy)',
          },
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredCards = _selectedTags.isEmpty
        ? _allCards
        : _allCards
            .where(
              (c) => c.tags.any((t) => _selectedTags.contains(t)),
            )
            .toList();

    final now = DateTime.now();
    final dueToday =
        filteredCards.where((c) => !c.nextDue.isAfter(now)).length;
    final dueLater =
        filteredCards.where((c) => c.nextDue.isAfter(now)).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('오답노트 · 복습'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _ReviewSummaryHeader(
              dueToday: dueToday,
              dueLater: dueLater,
              totalCards: filteredCards.length,
            ),
            const SizedBox(height: 12),
            _TodaysExpressionCard(
              expression: _currentExpression,
              onShuffle: _shuffleExpression,
            ),
            const SizedBox(height: 16),
            _TagFilterRow(
              allTags: _allTags,
              selectedTags: _selectedTags,
              onTagToggle: _toggleTag,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filteredCards.isEmpty
                  ? const Center(
                      child: Text('선택한 태그에 해당하는 오답 카드가 없어요.'),
                    )
                  : ListView.builder(
                      itemCount: filteredCards.length,
                      itemBuilder: (context, index) {
                        final card = filteredCards[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ReviewCardWidget(
                            card: card,
                            onGradeSelected: (grade) =>
                                _updateSrs(card, grade),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class ReviewCardModel {
  ReviewCardModel({
    required this.id,
    required this.question,
    required this.correctExpression,
    required this.explanation,
    required this.example,
    required this.tags,
    required this.nextDue,
    required this.lastReviewed,
    required this.wrongCount,
  });

  final String id;
  final String question;
  final String correctExpression;
  final String explanation;
  final String example;
  final List<String> tags;

  DateTime nextDue;
  DateTime lastReviewed;
  int wrongCount;

  bool get isDue => !nextDue.isAfter(DateTime.now());

  void applyGrade(SrsGrade grade) {
    final now = DateTime.now();
    lastReviewed = now;

    Duration interval;
    switch (grade) {
      case SrsGrade.again:
        interval = const Duration(minutes: 10);
        wrongCount += 1;
        break;
      case SrsGrade.hard:
        interval = const Duration(hours: 8);
        break;
      case SrsGrade.good:
        interval = const Duration(days: 1);
        break;
      case SrsGrade.easy:
        interval = const Duration(days: 3);
        break;
    }
    nextDue = now.add(interval);
  }
}

enum SrsGrade { again, hard, good, easy }

class TodaysExpression {
  final String phrase;
  final String meaning;
  final String example;
  final String tip;

  const TodaysExpression({
    required this.phrase,
    required this.meaning,
    required this.example,
    required this.tip,
  });
}

class _ReviewSummaryHeader extends StatelessWidget {
  final int dueToday;
  final int dueLater;
  final int totalCards;

  const _ReviewSummaryHeader({
    required this.dueToday,
    required this.dueLater,
    required this.totalCards,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.primaryContainer.withOpacity(0.5),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: _SummaryItem(
                label: '오늘 복습',
                value: '$dueToday',
              ),
            ),
            const VerticalDivider(thickness: 1),
            Expanded(
              child: _SummaryItem(
                label: '나중에',
                value: '$dueLater',
              ),
            ),
            const VerticalDivider(thickness: 1),
            Expanded(
              child: _SummaryItem(
                label: '전체 카드',
                value: '$totalCards',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _TodaysExpressionCard extends StatelessWidget {
  final TodaysExpression expression;
  final VoidCallback onShuffle;

  const _TodaysExpressionCard({
    required this.expression,
    required this.onShuffle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.primary.withOpacity(0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '오늘의 표현',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              expression.phrase,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              expression.meaning,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '예문',
              style: theme.textTheme.labelMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              expression.example,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Tip',
              style: theme.textTheme.labelMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              expression.tip,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onShuffle,
                icon: const Icon(Icons.refresh),
                label: const Text('다른 표현 보기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagFilterRow extends StatelessWidget {
  final List<String> allTags;
  final Set<String> selectedTags;
  final void Function(String tag) onTagToggle;

  const _TagFilterRow({
    required this.allTags,
    required this.selectedTags,
    required this.onTagToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '태그 필터',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              FilterChip(
                label: const Text('전체'),
                selected: selectedTags.isEmpty,
                onSelected: (_) {
                  for (final tag in allTags) {
                    if (selectedTags.contains(tag)) {
                      onTagToggle(tag);
                    }
                  }
                },
              ),
              const SizedBox(width: 8),
              ...allTags.map(
                (tag) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(tag),
                    selected: selectedTags.contains(tag),
                    onSelected: (_) => onTagToggle(tag),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ReviewCardWidget extends StatelessWidget {
  final ReviewCardModel card;
  final void Function(SrsGrade grade) onGradeSelected;

  const ReviewCardWidget({
    super.key,
    required this.card,
    required this.onGradeSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDue = card.isDue;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Wrap(
                  spacing: 4,
                  children: card.tags
                      .map((t) => Chip(
                            label: Text(
                              t,
                              style: theme.textTheme.labelSmall,
                            ),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ))
                      .toList(),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDue
                        ? theme.colorScheme.errorContainer.withOpacity(0.4)
                        : theme.colorScheme.secondaryContainer
                            .withOpacity(0.4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isDue ? '복습 필요' : '나중에',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '오답 문장',
              style: theme.textTheme.labelMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              card.question,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '올바른 표현',
              style: theme.textTheme.labelMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              card.correctExpression,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '설명',
              style: theme.textTheme.labelMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              card.explanation,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              '예문',
              style: theme.textTheme.labelMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              card.example,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.refresh,
                  size: 16,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(width: 4),
                Text(
                  '오답 횟수: ${card.wrongCount}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
                const Spacer(),
                Text(
                  _formatNextDue(card.nextDue),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SrsButtonRow(
              onGradeSelected: onGradeSelected,
            ),
          ],
        ),
      ),
    );
  }

  String _formatNextDue(DateTime dt) {
    final now = DateTime.now();
    final isToday =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;

    if (isToday) {
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      return '다음 복습: 오늘 $hh:$mm';
    } else {
      return '다음 복습: ${dt.month}/${dt.day}';
    }
  }
}

class _SrsButtonRow extends StatelessWidget {
  final void Function(SrsGrade grade) onGradeSelected;

  const _SrsButtonRow({required this.onGradeSelected});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        const labels = [
          'Again',
          'Hard',
          'Good',
          'Easy',
        ];
        const grades = [
          SrsGrade.again,
          SrsGrade.hard,
          SrsGrade.good,
          SrsGrade.easy,
        ];

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(labels.length, (index) {
            final label = labels[index];
            final grade = grades[index];

            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: index == labels.length - 1 ? 0 : 6,
                ),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    textStyle: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: () => onGradeSelected(grade),
                  child: Text(label),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}



