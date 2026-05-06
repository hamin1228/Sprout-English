import 'package:flutter/material.dart';

import 'roleplay_scenarios_exact.dart';
import 'roleplay_session_screen_exact.dart';

class RolePlayProgressScreenExact extends StatelessWidget {
  const RolePlayProgressScreenExact({super.key, required this.scenario});

  final RoleplayScenarioExact scenario;

  @override
  Widget build(BuildContext context) {
    return RoleplaySessionScreenExact(scenario: scenario, showSubtitles: false);
  }
}
