import 'package:flutter/material.dart';

import 'home_screen_exact.dart';
import 'settings_page.dart';
import 'statistics_page.dart';
import 'study_hub_page.dart';
import 'theme.dart';

enum MainTab { home, study, statistics, settings }

class MainTabShellPage extends StatefulWidget {
  const MainTabShellPage({
    super.key,
    this.initialTab = MainTab.home,
    this.nowProvider,
  });

  final MainTab initialTab;
  final DateTime Function()? nowProvider;

  @override
  State<MainTabShellPage> createState() => _MainTabShellPageState();
}

class _MainTabShellPageState extends State<MainTabShellPage> {
  static const _tabAnimationDuration = Duration(milliseconds: 260);

  late final PageController _pageController;
  late MainTab _currentTab;

  @override
  void initState() {
    super.initState();
    _currentTab = widget.initialTab;
    _pageController = PageController(initialPage: _currentTab.index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _selectTab(MainTab tab) async {
    if (_currentTab == tab) return;
    setState(() => _currentTab = tab);
    await _pageController.animateToPage(
      tab.index,
      duration: _tabAnimationDuration,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: (index) {
          setState(() => _currentTab = MainTab.values[index]);
        },
        children: [
          HomeScreenExact(
            showBottomNav: false,
            nowProvider: widget.nowProvider,
          ),
          const StudyHubPage(showAppBar: false),
          const StatisticsPage(showAppBar: false),
          const SettingsPage(showAppBar: false),
        ],
      ),
      bottomNavigationBar: _MainBottomNav(
        currentTab: _currentTab,
        onTabSelected: _selectTab,
      ),
    );
  }
}

class _MainBottomNav extends StatelessWidget {
  const _MainBottomNav({required this.currentTab, required this.onTabSelected});

  final MainTab currentTab;
  final ValueChanged<MainTab> onTabSelected;

  @override
  Widget build(BuildContext context) {
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
              _NavItem(
                icon: Icons.home,
                label: 'Home',
                active: currentTab == MainTab.home,
                onTap: () => onTabSelected(MainTab.home),
              ),
              _NavItem(
                icon: Icons.menu_book,
                label: 'Study',
                active: currentTab == MainTab.study,
                onTap: () => onTabSelected(MainTab.study),
              ),
              _NavItem(
                icon: Icons.bar_chart,
                label: 'Statistics',
                active: currentTab == MainTab.statistics,
                onTap: () => onTabSelected(MainTab.statistics),
              ),
              _NavItem(
                icon: Icons.settings,
                label: 'Settings',
                active: currentTab == MainTab.settings,
                onTap: () => onTabSelected(MainTab.settings),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: active ? AppTheme.primary : AppTheme.textSecondary,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: active ? AppTheme.primary : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
