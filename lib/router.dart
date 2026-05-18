import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/auth/auth_controller.dart';
import 'feature/auth/login_page.dart';
import 'feature/auth/signup_page.dart';
import 'feature/drill/drill_page.dart';
import 'feature/free_talk/free_talk_page.dart';
import 'feature/healthz/healthz_page.dart';
import 'feature/paraphrase/paraphrase_page.dart';
import 'feature/review/review_page.dart';
import 'feature/roleplay/roleplay_page.dart';
import 'feature/speaking/speaking_page.dart';
import 'screens/main_tab_shell_page.dart';
import 'feature/vocab/vocab_page.dart';
import 'feature/writing/toeic_writing_page.dart';
import 'feature/writing/writing_hub_page.dart';
import 'screens/grammar_check_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: _AuthListenable(ref),
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final isLoading = auth.status == AuthStatus.loading;
      final isAuthenticated = auth.status == AuthStatus.authenticated;
      final loc = state.matchedLocation;
      final isAuthRoute = loc == '/login' || loc == '/signup';

      if (isLoading) return null;
      if (!isAuthenticated && !isAuthRoute) return '/login';
      if (isAuthenticated && isAuthRoute) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/signup',
        name: 'signup',
        builder: (context, state) => const SignupPage(),
      ),
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const MainTabShellPage(),
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

// GoRouter refreshListenable에 Riverpod 인증 상태 변화를 연결하는 헬퍼
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Ref ref) {
    ref.listen(authControllerProvider, (_, __) => notifyListeners());
  }
}
