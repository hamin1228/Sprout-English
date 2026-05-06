import 'dart:async';

import 'package:flutter/material.dart';

import '../core/profile/user_profile.dart';
import '../core/profile/user_profile_store.dart';
import '../core/statistics/home_progress_summary.dart';
import '../core/statistics/learning_activity_store.dart';
import '../core/statistics/statistics_aggregator.dart';
import '../core/statistics/statistics_models.dart';
import '../feature/writing/toeic_writing_page.dart';
import '../feature/writing/writing_hub_page.dart';
import '../widgets/profile_avatar.dart';
import 'push_to_talk_freetalk_screen_exact.dart';
import 'roleplay_settings_screen_exact.dart';
import 'settings_page.dart';
import 'statistics_page.dart';
import 'study_hub_page.dart';
import 'theme.dart';
import 'todays_expressions_data.dart';

String greetingPrefixForTime(DateTime now) {
  final hour = now.hour;
  if (hour >= 5 && hour < 12) return 'Good morning';
  if (hour >= 12 && hour < 18) return 'Good afternoon';
  return 'Good evening';
}

/// 홈 화면 - HTML 디자인 완전 복제
/// "Good morning, Alex!" + Today's Expression + Quick Access
class HomeScreenExact extends StatefulWidget {
  const HomeScreenExact({
    super.key,
    this.showBottomNav = true,
    this.nowProvider,
  });

  final bool showBottomNav;
  final DateTime Function()? nowProvider;

  @override
  State<HomeScreenExact> createState() => _HomeScreenExactState();
}

class _HomeScreenExactState extends State<HomeScreenExact> {
  final UserProfileStore _profileStore = UserProfileStore.instance;
  final LearningActivityStore _activityStore = LearningActivityStore.instance;
  final PageController _expressionPageController = PageController();

  UserProfile _profile = const UserProfile();
  HomeProgressSummary _progressSummary = const HomeProgressSummary.empty();
  int _expressionPageIndex = 0;
  bool _loadingProgressSummary = true;

  @override
  void initState() {
    super.initState();
    unawaited(_reloadHomeData());
  }

  @override
  void dispose() {
    _expressionPageController.dispose();
    super.dispose();
  }

  Future<void> _reloadHomeData() async {
    final profile = await _profileStore.load();
    final progressSummary = await _loadProgressSummary();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _progressSummary = progressSummary;
      _loadingProgressSummary = false;
    });
  }

  Future<HomeProgressSummary> _loadProgressSummary() async {
    final records = await _activityStore.load();
    final snapshot = StatisticsAggregator.build(
      records: records,
      range: StatisticsRange.all,
    );
    return HomeProgressSummary.fromOverview(snapshot.overview);
  }

  Future<void> _openPage(BuildContext context, Widget screen) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));
    if (!mounted) return;
    await _reloadHomeData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTodaysExpressionPager(),
                    const SizedBox(height: 28),
                    const Text(
                      'Quick Access',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(child: _buildQuickAccessGrid()),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: widget.showBottomNav
          ? _buildBottomNav(context)
          : null,
    );
  }

  Widget _buildHeader() {
    final now = (widget.nowProvider ?? DateTime.now)();
    final greetingPrefix = greetingPrefixForTime(now);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(color: AppTheme.backgroundLight),
      child: Row(
        children: [
          ProfileAvatar(
            size: 40,
            imagePath: _profile.avatarImagePath,
            zoom: _profile.avatarZoom,
            offset: _profile.avatarOffsetForSize(40),
            placeholderIconSize: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$greetingPrefix, ${_profile.displayName}!',
              key: const ValueKey('home_greeting'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            color: AppTheme.textDark,
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildTodaysExpressionPager() {
    return SizedBox(
      height: 180,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderLight),
        ),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: PageView(
                key: const ValueKey('home_expression_pageview'),
                controller: _expressionPageController,
                onPageChanged: (index) {
                  setState(() => _expressionPageIndex = index);
                },
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                    child: _buildExpressionPage(),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                    child: _buildProgressSummaryPage(),
                  ),
                ],
              ),
            ),
            Positioned(right: 16, bottom: 12, child: _buildPagerIndicator()),
          ],
        ),
      ),
    );
  }

  Widget _buildExpressionPage() {
    return FutureBuilder<TodaysExpression>(
      future: TodaysExpressionRepository.loadRandomForRun(),
      builder: (context, snapshot) {
        final expression = snapshot.data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Today\'s Expression',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '"${expression?.expression ?? 'Loading...'}"',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              expression?.meaning ?? '표현을 불러오는 중입니다.',
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProgressSummaryPage() {
    if (_loadingProgressSummary) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (!_progressSummary.hasRecords) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '연속 학습',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
          SizedBox(height: 12),
          Text(
            '아직 학습 기록이 없습니다',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.textDark,
            ),
          ),
          SizedBox(height: 10),
          Text(
            '첫 학습을 시작하면 연속 학습이 쌓입니다.',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '연속 학습',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: AppTheme.textDark,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${_progressSummary.streakDays}일',
          key: const ValueKey('home_streak_value'),
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: AppTheme.textDark,
            height: 1,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _buildSummaryStat('총 세션', '${_progressSummary.totalSessions}회'),
            const SizedBox(width: 12),
            _buildSummaryStat(
              '총 학습 시간',
              _formatDuration(_progressSummary.totalDurationSec),
            ),
            const SizedBox(width: 12),
            _buildSummaryStat(
              '최근 학습일',
              _formatDate(_progressSummary.latestActivity),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryStat(String title, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F7FB),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPagerIndicator() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(2, (index) {
        final selected = _expressionPageIndex == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: EdgeInsets.only(left: index == 0 ? 0 : 6),
          width: selected ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary : const Color(0xFFD3D9E6),
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }

  Widget _buildQuickAccessGrid() {
    final items = [
      {
        'icon': Icons.chat,
        'label': 'Free Talking',
        'color': AppTheme.primary,
        'screen': const PushToTalkFreeTalkScreenExact(),
      },
      {
        'icon': Icons.edit_note,
        'label': 'Writing',
        'color': AppTheme.success,
        'screen': const WritingHubPage(),
      },
      {
        'icon': Icons.groups,
        'label': 'Role-playing',
        'color': const Color(0xFFFF9800),
        'screen': const RolePlaySettingsScreenExact(),
      },
      {
        'icon': Icons.school,
        'label': 'TOEIC',
        'color': const Color(0xFF9C27B0),
        'screen': const ToeicWritingPage(),
      },
    ];

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _buildQuickAccessCard(
          icon: item['icon'] as IconData,
          label: item['label'] as String,
          color: item['color'] as Color,
          onTap: () {
            final screen = item['screen'] as Widget?;
            if (screen == null) return;
            unawaited(_openPage(context, screen));
          },
        );
      },
    );
  }

  Widget _buildQuickAccessCard({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.borderLight),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.borderLight)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 80,
          child: Row(
            children: [
              _buildNavItem(Icons.home, 'Home', true),
              _buildNavItem(
                Icons.menu_book,
                'Study',
                false,
                onTap: () =>
                    unawaited(_openPage(context, const StudyHubPage())),
              ),
              _buildNavItem(
                Icons.bar_chart,
                'Statistics',
                false,
                onTap: () =>
                    unawaited(_openPage(context, const StatisticsPage())),
              ),
              _buildNavItem(
                Icons.settings,
                'Settings',
                false,
                onTap: () =>
                    unawaited(_openPage(context, const SettingsPage())),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    IconData icon,
    String label,
    bool isActive, {
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isActive ? AppTheme.primary : AppTheme.textSecondary,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isActive ? AppTheme.primary : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$month/$day';
  }

  String _formatDuration(int durationSec) {
    final hours = durationSec ~/ 3600;
    final minutes = (durationSec % 3600) ~/ 60;
    if (hours > 0) {
      return minutes > 0 ? '$hours시간 $minutes분' : '$hours시간';
    }
    if (minutes > 0) return '$minutes분';
    return '${durationSec.clamp(0, 59)}초';
  }
}
