import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_api.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_token_storage.dart';
import 'server_config.dart';

final _tokenStorage = AuthTokenStorage();

// 동시에 여러 요청이 401을 받아도 refresh는 1회만 실행됨
Completer<String?>? _tokenRefreshCompleter;

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) async {
      options.baseUrl = serverBaseUrl;

      final path = options.path;
      final skipAuth = path.contains('/auth/login') ||
          path.contains('/auth/signup') ||
          path.contains('/auth/refresh');

      if (!skipAuth) {
        final token = await _tokenStorage.getAccessToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
      }

      handler.next(options);
    },
    onError: (error, handler) async {
      final opts = error.requestOptions;
      final path = opts.path;
      final isAuthRoute = path.contains('/auth/login') ||
          path.contains('/auth/signup') ||
          path.contains('/auth/refresh');
      final alreadyRetried = opts.extra['_retried'] == true;

      if (error.response?.statusCode == 401 && !isAuthRoute && !alreadyRetried) {
        String? newAccessToken;

        if (_tokenRefreshCompleter != null) {
          // 이미 다른 요청이 refresh 중 → 완료 대기
          newAccessToken = await _tokenRefreshCompleter!.future;
        } else {
          _tokenRefreshCompleter = Completer<String?>();
          try {
            final refreshToken = await _tokenStorage.getRefreshToken();
            if (refreshToken == null || refreshToken.isEmpty) {
              throw Exception('No refresh token');
            }
            final resp = await authApi.refresh(refreshToken);
            await _tokenStorage.saveTokens(
              accessToken: resp.accessToken,
              refreshToken: resp.refreshToken,
            );
            newAccessToken = resp.accessToken;
            _tokenRefreshCompleter!.complete(newAccessToken);
          } catch (_) {
            _tokenRefreshCompleter!.complete(null);
            newAccessToken = null;
          } finally {
            _tokenRefreshCompleter = null;
          }
        }

        if (newAccessToken != null) {
          opts.headers['Authorization'] = 'Bearer $newAccessToken';
          opts.extra['_retried'] = true;
          try {
            final response = await dio.fetch(opts);
            handler.resolve(response);
          } catch (_) {
            handler.next(error);
          }
          return;
        } else {
          await _tokenStorage.clearTokens();
          ref.read(authControllerProvider.notifier).forceUnauthenticated();
          handler.next(error);
          return;
        }
      }

      handler.next(error);
    },
  ));
  return dio;
});
