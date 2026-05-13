import 'package:dio/dio.dart';

import '../network/server_config.dart';
import 'auth_models.dart';
import 'auth_token_storage.dart';

class AuthApi {
  AuthApi() : _dio = _buildDio();

  static Dio _buildDio() {
    return Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ));
  }

  final Dio _dio;

  String get _base => serverBaseUrl;

  Future<AuthResponse> signup({
    required String email,
    required String password,
    String? nickname,
  }) async {
    final resp = await _dio.post(
      '$_base/auth/signup',
      data: {'email': email, 'password': password, 'nickname': nickname},
    );
    return AuthResponse.fromJson(Map<String, dynamic>.from(resp.data as Map));
  }

  Future<AuthResponse> login({
    required String email,
    required String password,
  }) async {
    final resp = await _dio.post(
      '$_base/auth/login',
      data: {'email': email, 'password': password},
    );
    return AuthResponse.fromJson(Map<String, dynamic>.from(resp.data as Map));
  }

  Future<AuthResponse> refresh(String refreshToken) async {
    final resp = await _dio.post(
      '$_base/auth/refresh',
      data: {'refresh_token': refreshToken},
    );
    return AuthResponse.fromJson(Map<String, dynamic>.from(resp.data as Map));
  }

  Future<AuthUser> me(String accessToken) async {
    final resp = await _dio.get(
      '$_base/auth/me',
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    return AuthUser.fromJson(Map<String, dynamic>.from(resp.data as Map));
  }

  Future<void> logout(String accessToken) async {
    await _dio.post(
      '$_base/auth/logout',
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
  }
}

final authApi = AuthApi();
final authTokenStorage = AuthTokenStorage();
