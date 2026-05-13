import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_api.dart';
import 'auth_models.dart';

enum AuthStatus { loading, authenticated, unauthenticated }

class AuthState {
  const AuthState({
    required this.status,
    this.user,
    this.errorMessage,
  });

  final AuthStatus status;
  final AuthUser? user;
  final String? errorMessage;

  bool get isLoading => status == AuthStatus.loading;
  bool get isAuthenticated => status == AuthStatus.authenticated;

  AuthState copyWith({
    AuthStatus? status,
    AuthUser? user,
    String? errorMessage,
  }) =>
      AuthState(
        status: status ?? this.status,
        user: user ?? this.user,
        errorMessage: errorMessage,
      );
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState(status: AuthStatus.loading);

  Future<void> bootstrap() async {
    state = const AuthState(status: AuthStatus.loading);
    try {
      final token = await authTokenStorage.getAccessToken();
      if (token == null || token.isEmpty) {
        state = const AuthState(status: AuthStatus.unauthenticated);
        return;
      }
      final user = await authApi.me(token);
      state = AuthState(status: AuthStatus.authenticated, user: user);
    } catch (_) {
      await authTokenStorage.clearTokens();
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<void> signup({
    required String email,
    required String password,
    String? nickname,
  }) async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);
    try {
      final resp = await authApi.signup(email: email, password: password, nickname: nickname);
      await authTokenStorage.saveTokens(
        accessToken: resp.accessToken,
        refreshToken: resp.refreshToken,
      );
      state = AuthState(status: AuthStatus.authenticated, user: resp.user);
    } on DioException catch (e) {
      state = AuthState(
        status: AuthStatus.unauthenticated,
        errorMessage: _parseDioError(e),
      );
    } catch (e) {
      state = AuthState(
        status: AuthStatus.unauthenticated,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);
    try {
      final resp = await authApi.login(email: email, password: password);
      await authTokenStorage.saveTokens(
        accessToken: resp.accessToken,
        refreshToken: resp.refreshToken,
      );
      state = AuthState(status: AuthStatus.authenticated, user: resp.user);
    } on DioException catch (e) {
      state = AuthState(
        status: AuthStatus.unauthenticated,
        errorMessage: _parseDioError(e),
      );
    } catch (e) {
      state = AuthState(
        status: AuthStatus.unauthenticated,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> logout() async {
    try {
      final token = await authTokenStorage.getAccessToken();
      if (token != null) await authApi.logout(token);
    } catch (_) {
      // 서버 로그아웃 실패해도 로컬 토큰은 반드시 삭제
    }
    await authTokenStorage.clearTokens();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  String _parseDioError(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['detail'] != null) return data['detail'].toString();
    return e.message ?? '알 수 없는 오류가 발생했습니다.';
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);
