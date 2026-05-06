import 'package:flutter/material.dart';

import '../core/settings/app_settings_store.dart';
import 'roleplay_progress_screen_exact.dart';
import 'roleplay_progress_with_subtitles_screen_exact.dart';
import 'roleplay_scenarios_exact.dart';
import 'theme.dart';

/// 롤플레잉 설정 화면 - 난이도 선택 + 시나리오 선택 + 자막 토글
class RolePlaySettingsScreenExact extends StatefulWidget {
  const RolePlaySettingsScreenExact({super.key});

  @override
  State<RolePlaySettingsScreenExact> createState() =>
      _RolePlaySettingsScreenExactState();
}

class _RolePlaySettingsScreenExactState
    extends State<RolePlaySettingsScreenExact> {
  String _selectedDifficulty = '초급';
  bool _subtitlesEnabled = false;
  RoleplayScenarioExact? _selectedScenario;

  @override
  void initState() {
    super.initState();
    _selectedScenario = RoleplayScenarioCatalogExact.byDifficulty(
      _selectedDifficulty,
    ).first;
    _loadDefaults();
  }

  List<RoleplayScenarioExact> get _scenarios =>
      RoleplayScenarioCatalogExact.byDifficulty(_selectedDifficulty);

  Future<void> _loadDefaults() async {
    final settings = await AppSettingsStore.instance.load();
    final difficulty = _difficultyLabelFromSetting(settings.defaultDifficulty);
    final scenarios = RoleplayScenarioCatalogExact.byDifficulty(difficulty);
    if (!mounted || scenarios.isEmpty) return;

    setState(() {
      _selectedDifficulty = difficulty;
      _subtitlesEnabled = settings.roleplaySubtitleDefault;
      _selectedScenario = scenarios.first;
    });
  }

  String _difficultyLabelFromSetting(String difficulty) {
    switch (difficulty) {
      case 'intermediate':
        return '중급';
      case 'advanced':
        return '고급';
      case 'beginner':
      default:
        return '초급';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundLight.withValues(alpha: 0.92),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '어떤 상황을 연습해볼까요?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.textDark,
          ),
        ),
      ),
      body: Column(
        children: [
          _buildDifficultySelector(),
          Expanded(child: _buildScenarioGrid()),
          _buildBottomActions(context),
        ],
      ),
    );
  }

  Widget _buildDifficultySelector() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Row(
        children: ['초급', '중급', '고급'].map((level) {
          final isSelected = _selectedDifficulty == level;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                final scenarios = RoleplayScenarioCatalogExact.byDifficulty(
                  level,
                );
                setState(() {
                  _selectedDifficulty = level;
                  _selectedScenario = scenarios.first;
                });
              },
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(9999),
                  boxShadow: isSelected
                      ? [const BoxShadow(color: Colors.black12, blurRadius: 4)]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  level,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isSelected
                        ? AppTheme.textDark
                        : AppTheme.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildScenarioGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.85,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _scenarios.length,
      itemBuilder: (context, index) {
        final scenario = _scenarios[index];
        return _buildScenarioCard(scenario: scenario);
      },
    );
  }

  Widget _buildScenarioCard({required RoleplayScenarioExact scenario}) {
    final isSelected = _selectedScenario?.id == scenario.id;
    return GestureDetector(
      onTap: () => setState(() => _selectedScenario = scenario),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: isSelected
              ? Border.all(color: AppTheme.primary, width: 3)
              : null,
          image: DecorationImage(
            image: AssetImage(scenario.backgroundAsset),
            fit: BoxFit.cover,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.25),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.58),
              ],
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primary
                        : Colors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isSelected ? Icons.check : Icons.play_arrow,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                scenario.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                scenario.subtitle,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomActions(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.backgroundLight.withValues(alpha: 0.9),
        border: Border(top: BorderSide(color: AppTheme.borderLight)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.borderLight),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '연습 중 자막을 보시겠어요?',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _subtitlesEnabled
                              ? '자막 있는 진행 화면으로 이동'
                              : '자막 없는 진행 화면으로 이동',
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _subtitlesEnabled,
                    onChanged: (value) =>
                        setState(() => _subtitlesEnabled = value),
                    activeThumbColor: AppTheme.primary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _selectedScenario == null
                    ? null
                    : () {
                        final scenario = _selectedScenario!;
                        final Widget nextScreen = _subtitlesEnabled
                            ? RolePlayProgressWithSubtitlesScreenExact(
                                scenario: scenario,
                              )
                            : RolePlayProgressScreenExact(scenario: scenario);
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => nextScreen),
                        );
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9999),
                  ),
                ),
                child: Text(
                  _subtitlesEnabled ? '자막과 함께 시작' : '자막 없이 시작',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
