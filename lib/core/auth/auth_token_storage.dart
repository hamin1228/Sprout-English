import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _kAccessToken = 'access_token';
const _kRefreshToken = 'refresh_token';

class AuthTokenStorage {
  AuthTokenStorage() : _storage = const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      _storage.write(key: _kAccessToken, value: accessToken),
      _storage.write(key: _kRefreshToken, value: refreshToken),
    ]);
  }

  Future<String?> getAccessToken() => _storage.read(key: _kAccessToken);

  Future<String?> getRefreshToken() => _storage.read(key: _kRefreshToken);

  Future<void> clearTokens() async {
    await Future.wait([
      _storage.delete(key: _kAccessToken),
      _storage.delete(key: _kRefreshToken),
    ]);
  }

  Future<bool> hasAccessToken() async {
    final token = await _storage.read(key: _kAccessToken);
    return token != null && token.isNotEmpty;
  }
}
