// FILE: test/auth_state_test.dart
import 'package:english_ai/core/auth/auth_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthState', () {
    test('loading 상태는 isLoading=true, isAuthenticated=false', () {
      const state = AuthState(status: AuthStatus.loading);
      expect(state.isLoading, true);
      expect(state.isAuthenticated, false);
      expect(state.errorMessage, isNull);
    });

    test('authenticated 상태는 isLoading=false, isAuthenticated=true', () {
      const state = AuthState(status: AuthStatus.authenticated);
      expect(state.isLoading, false);
      expect(state.isAuthenticated, true);
    });

    test('unauthenticated 상태는 isLoading=false, isAuthenticated=false', () {
      const state = AuthState(status: AuthStatus.unauthenticated);
      expect(state.isLoading, false);
      expect(state.isAuthenticated, false);
    });

    test('copyWith: status만 변경하면 errorMessage는 null로 초기화됨', () {
      const original = AuthState(
        status: AuthStatus.loading,
        errorMessage: '오류',
      );
      final copied = original.copyWith(status: AuthStatus.unauthenticated);
      expect(copied.status, AuthStatus.unauthenticated);
      expect(copied.errorMessage, isNull);
    });

    test('errorMessage 포함 AuthState 생성', () {
      const state = AuthState(
        status: AuthStatus.unauthenticated,
        errorMessage: '이메일 또는 비밀번호가 틀렸습니다.',
      );
      expect(state.errorMessage, '이메일 또는 비밀번호가 틀렸습니다.');
      expect(state.isAuthenticated, false);
    });
  });
}
