import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'feature/drill/drill_page.dart';
import 'feature/free_talk/free_talk_page.dart';
import 'feature/healthz/healthz_page.dart';
import 'feature/local_stt/local_stt_switch_page.dart';
import 'feature/paraphrase/paraphrase_page.dart';
import 'feature/record/record_page.dart';
import 'feature/review/review_page.dart';
import 'feature/roleplay/roleplay_page.dart';
import 'feature/speaking/speaking_page.dart';
import 'feature/vocab/vocab_page.dart';
import 'feature/writing/toeic_writing_page.dart';
import 'feature/writing/writing_hub_page.dart';
import 'screens/grammar_check_screen.dart';

final appRouterLocalSttProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/local_stt_switch',
    routes: [
      GoRoute(
        path: '/local_stt_switch',
        name: 'local_stt_switch',
        builder: (context, state) => const LocalSttSwitchPage(),
      ),
      GoRoute(
        path: '/',
        name: 'record',
        builder: (context, state) => const RecordPage(),
      ),
      GoRoute(
        path: '/healthz',
        name: 'healthz',
        builder: (context, state) => const HealthzPage(),
      ),
      GoRoute(
        path: '/free_talk',
        name: 'free_talk',
        builder: (context, state) => const FreeTalkPage(),
      ),
      GoRoute(
        path: '/speaking',
        name: 'speaking',
        builder: (context, state) => const SpeakingPage(),
      ),
      GoRoute(
        path: '/writing',
        name: 'writing',
        builder: (context, state) => const WritingHubPage(),
        routes: [
          GoRoute(
            path: 'grammar',
            name: 'writing_grammar',
            builder: (context, state) => const GrammarCheckScreen(),
          ),
          GoRoute(
            path: 'tone',
            name: 'writing_tone',
            builder: (context, state) => const ParaphrasePage(),
          ),
          GoRoute(
            path: 'toeic',
            name: 'writing_toeic',
            builder: (context, state) => const ToeicWritingPage(),
          ),
        ],
      ),
      GoRoute(
        path: '/roleplay',
        name: 'roleplay',
        builder: (context, state) => const RoleplayPage(),
      ),
      GoRoute(
        path: '/drill',
        name: 'drill',
        builder: (context, state) => const DrillPage(),
      ),
      GoRoute(
        path: '/paraphrase',
        name: 'paraphrase',
        builder: (context, state) => const ParaphrasePage(),
      ),
      GoRoute(
        path: '/review',
        name: 'review',
        builder: (context, state) => const ReviewPage(),
      ),
      GoRoute(
        path: '/vocab',
        name: 'vocab',
        builder: (context, state) => const VocabPage(),
      ),
    ],
  );
});
