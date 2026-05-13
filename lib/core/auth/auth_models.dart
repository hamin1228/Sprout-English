class AuthUser {
  const AuthUser({
    required this.publicId,
    required this.email,
    required this.nickname,
    required this.isActive,
    required this.createdAt,
  });

  final String publicId;
  final String email;
  final String? nickname;
  final bool isActive;
  final DateTime createdAt;

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        publicId: json['public_id'] as String,
        email: json['email'] as String,
        nickname: json['nickname'] as String?,
        isActive: json['is_active'] as bool,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class AuthResponse {
  const AuthResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final String tokenType;
  final AuthUser user;

  factory AuthResponse.fromJson(Map<String, dynamic> json) => AuthResponse(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
        tokenType: json['token_type'] as String? ?? 'bearer',
        user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
      );
}
