import 'dart:io';

import 'package:flutter/material.dart';

import '../screens/theme.dart';

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.size,
    this.imagePath,
    this.zoom = 1.0,
    this.offset = Offset.zero,
    this.placeholderIcon = Icons.person,
    this.placeholderIconSize,
    this.backgroundColor,
  });

  final double size;
  final String? imagePath;
  final double zoom;
  final Offset offset;
  final IconData placeholderIcon;
  final double? placeholderIconSize;
  final Color? backgroundColor;

  static Offset clampOffset({
    required double viewportSize,
    required double zoom,
    required Offset offset,
  }) {
    final renderedSize = viewportSize * zoom.clamp(1.0, 4.0);
    final maxDelta = ((renderedSize - viewportSize) / 2).clamp(
      0.0,
      double.infinity,
    );
    return Offset(
      offset.dx.clamp(-maxDelta, maxDelta).toDouble(),
      offset.dy.clamp(-maxDelta, maxDelta).toDouble(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (imagePath == null || imagePath!.isEmpty) {
      return _buildPlaceholder();
    }

    final file = File(imagePath!);
    if (!file.existsSync()) {
      return _buildPlaceholder();
    }

    final renderedSize = size * zoom.clamp(1.0, 4.0);
    final clampedOffset = clampOffset(
      viewportSize: size,
      zoom: zoom,
      offset: offset,
    );

    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: backgroundColor ?? const Color(0xFFF2F2F7),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Transform.translate(
              offset: clampedOffset,
              child: SizedBox(
                width: renderedSize,
                height: renderedSize,
                child: Image.file(file, fit: BoxFit.cover),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor ?? const Color(0xFFF2F2F7),
      ),
      child: Icon(
        placeholderIcon,
        size: placeholderIconSize ?? (size * 0.55),
        color: AppTheme.textSecondary.withValues(alpha: 0.7),
      ),
    );
  }
}
