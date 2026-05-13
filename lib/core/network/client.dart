import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_token_storage.dart';
import 'server_config.dart';

// TODO: 401 응답 시 refresh_token으로 access_token 재발급 후 원래 요청 재시도 로직 추가 필요
//       현재는 Authorization 헤더 자동 첨부까지만 구현됨.

final _tokenStorage = AuthTokenStorage();

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

      // /auth/login, /auth/signup, /auth/refresh는 토큰 없이 호출
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
  ));
  return dio;
});
