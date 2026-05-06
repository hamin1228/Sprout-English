import 'package:flutter/material.dart';

class UserProfileStorageKeys {
  static const displayName = 'display_name';
  static const avatarImagePath = 'avatar_image_path';
  static const avatarZoom = 'avatar_zoom';
  static const avatarOffsetDx = 'avatar_offset_dx';
  static const avatarOffsetDy = 'avatar_offset_dy';
}

class UserProfile {
  static const double legacyEditorViewportSize = 260.0;

  const UserProfile({
    this.displayName = 'Alex',
    this.avatarImagePath,
    this.avatarZoom = 1.0,
    this.avatarOffsetDx = 0,
    this.avatarOffsetDy = 0,
  });

  final String displayName;
  final String? avatarImagePath;
  final double avatarZoom;
  final double avatarOffsetDx;
  final double avatarOffsetDy;

  Offset get avatarOffsetFactor => Offset(
    _normalizeStoredOffset(avatarOffsetDx),
    _normalizeStoredOffset(avatarOffsetDy),
  );

  Offset avatarOffsetForSize(double viewportSize) {
    final factor = avatarOffsetFactor;
    return Offset(factor.dx * viewportSize, factor.dy * viewportSize);
  }

  static Offset offsetFactorFromPixels(
    Offset offset, {
    double viewportSize = legacyEditorViewportSize,
  }) {
    if (viewportSize <= 0) {
      return Offset.zero;
    }
    return Offset(offset.dx / viewportSize, offset.dy / viewportSize);
  }

  UserProfile copyWith({
    String? displayName,
    String? avatarImagePath,
    bool clearAvatarImagePath = false,
    double? avatarZoom,
    double? avatarOffsetDx,
    double? avatarOffsetDy,
  }) {
    return UserProfile(
      displayName: _normalizeDisplayName(displayName ?? this.displayName),
      avatarImagePath: clearAvatarImagePath
          ? null
          : (avatarImagePath ?? this.avatarImagePath),
      avatarZoom: _normalizeZoom(avatarZoom ?? this.avatarZoom),
      avatarOffsetDx: avatarOffsetDx ?? this.avatarOffsetDx,
      avatarOffsetDy: avatarOffsetDy ?? this.avatarOffsetDy,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      UserProfileStorageKeys.displayName: displayName,
      UserProfileStorageKeys.avatarImagePath: avatarImagePath,
      UserProfileStorageKeys.avatarZoom: avatarZoom,
      UserProfileStorageKeys.avatarOffsetDx: avatarOffsetDx,
      UserProfileStorageKeys.avatarOffsetDy: avatarOffsetDy,
    };
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      displayName: _normalizeDisplayName(
        json[UserProfileStorageKeys.displayName] as String? ?? 'Alex',
      ),
      avatarImagePath: json[UserProfileStorageKeys.avatarImagePath] as String?,
      avatarZoom: _normalizeZoom(
        (json[UserProfileStorageKeys.avatarZoom] as num?)?.toDouble() ?? 1.0,
      ),
      avatarOffsetDx:
          (json[UserProfileStorageKeys.avatarOffsetDx] as num?)?.toDouble() ??
          0,
      avatarOffsetDy:
          (json[UserProfileStorageKeys.avatarOffsetDy] as num?)?.toDouble() ??
          0,
    );
  }

  static String _normalizeDisplayName(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? 'Alex' : trimmed;
  }

  static double _normalizeZoom(double value) {
    if (value.isNaN || !value.isFinite) {
      return 1.0;
    }
    return value.clamp(1.0, 4.0).toDouble();
  }

  static double _normalizeStoredOffset(double value) {
    if (value.isNaN || !value.isFinite) {
      return 0;
    }
    if (value.abs() > 4) {
      return value / legacyEditorViewportSize;
    }
    return value;
  }
}
