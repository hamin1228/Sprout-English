import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../core/profile/user_profile.dart';
import '../core/profile/user_profile_store.dart';
import '../widgets/profile_avatar.dart';
import 'theme.dart';

const double _profileEditorViewportSize = UserProfile.legacyEditorViewportSize;

/// 프로필 설정 화면
/// 프로필 사진 + 이름 입력 + 완료 버튼
class ProfileSettingsScreenExact extends StatefulWidget {
  const ProfileSettingsScreenExact({super.key});

  @override
  State<ProfileSettingsScreenExact> createState() =>
      _ProfileSettingsScreenExactState();
}

class _ProfileSettingsScreenExactState
    extends State<ProfileSettingsScreenExact> {
  final UserProfileStore _profileStore = UserProfileStore.instance;
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _nameController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _avatarImagePath;
  double _avatarZoom = 1.0;
  Offset _avatarOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    unawaited(_loadProfile());
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final profile = await _profileStore.load();
    if (!mounted) return;
    setState(() {
      _nameController.text = profile.displayName;
      _avatarImagePath = profile.avatarImagePath;
      _avatarZoom = profile.avatarZoom;
      _avatarOffset = profile.avatarOffsetForSize(_profileEditorViewportSize);
      _loading = false;
    });
  }

  Future<void> _pickAvatarImage() async {
    try {
      final pickedImage = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
      );
      if (pickedImage == null || !mounted) return;

      final edit = await Navigator.of(context).push<_AvatarEditResult>(
        MaterialPageRoute<_AvatarEditResult>(
          builder: (_) => _ProfilePhotoEditorPage(
            imagePath: pickedImage.path,
            initialZoom: 1.0,
            initialOffset: Offset.zero,
          ),
        ),
      );
      if (edit == null || !mounted) return;

      final storedPath = await _profileStore.importAvatarFile(
        pickedImage.path,
        previousPath: _avatarImagePath,
      );
      if (!mounted) return;

      setState(() {
        _avatarImagePath = storedPath;
        _avatarZoom = edit.zoom;
        _avatarOffset = edit.offset;
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      final message =
          error.code == 'channel-error' ||
              (error.message?.contains(
                    'Unable to establish connection on channel',
                  ) ??
                  false)
          ? '사진 선택 기능이 현재 실행 중인 앱에 아직 연결되지 않았습니다. 앱을 완전히 종료한 뒤 다시 실행해 주세요.'
          : '사진을 불러오지 못했습니다: ${error.message ?? error.code}';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('사진을 불러오지 못했습니다: $error')));
    }
  }

  Future<void> _showAvatarActions() async {
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '프로필 사진',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('갤러리에서 선택'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickAvatarImage();
                  },
                ),
                if (_avatarImagePath != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.open_with),
                    title: const Text('현재 사진 조정'),
                    onTap: () {
                      Navigator.of(context).pop();
                      _adjustCurrentAvatar();
                    },
                  ),
                if (_avatarImagePath != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.delete_outline,
                      color: Color(0xFFD14343),
                    ),
                    title: const Text(
                      '사진 삭제',
                      style: TextStyle(color: Color(0xFFD14343)),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      _removeAvatar();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _adjustCurrentAvatar() async {
    final currentPath = _avatarImagePath;
    if (currentPath == null || currentPath.isEmpty) return;

    final edit = await Navigator.of(context).push<_AvatarEditResult>(
      MaterialPageRoute<_AvatarEditResult>(
        builder: (_) => _ProfilePhotoEditorPage(
          imagePath: currentPath,
          initialZoom: _avatarZoom,
          initialOffset: _avatarOffset,
        ),
      ),
    );
    if (edit == null || !mounted) return;

    setState(() {
      _avatarZoom = edit.zoom;
      _avatarOffset = edit.offset;
    });
  }

  void _removeAvatar() {
    setState(() {
      _avatarImagePath = null;
      _avatarZoom = 1.0;
      _avatarOffset = Offset.zero;
    });
  }

  Future<void> _saveProfile() async {
    if (_saving) return;

    setState(() => _saving = true);

    final nextProfile = UserProfile(
      displayName: _nameController.text.trim(),
      avatarImagePath: _avatarImagePath,
      avatarZoom: _avatarZoom,
      avatarOffsetDx: UserProfile.offsetFactorFromPixels(
        _avatarOffset,
        viewportSize: _profileEditorViewportSize,
      ).dx,
      avatarOffsetDy: UserProfile.offsetFactorFromPixels(
        _avatarOffset,
        viewportSize: _profileEditorViewportSize,
      ).dy,
    );
    await _profileStore.save(nextProfile);

    if (!mounted) return;
    setState(() => _saving = false);

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('프로필을 저장했습니다.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundLight,
        elevation: 0,
        title: const Text(
          '프로필 설정',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.textDark,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Expanded(
                      child: ListView(
                        children: [
                          const SizedBox(height: 12),
                          Center(
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: _showAvatarActions,
                                child: Stack(
                                  children: [
                                    Container(
                                      width: 144,
                                      height: 144,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.black.withValues(
                                            alpha: 0.1,
                                          ),
                                          width: 2,
                                        ),
                                      ),
                                      child: ProfileAvatar(
                                        size: 140,
                                        imagePath: _avatarImagePath,
                                        zoom: _avatarZoom,
                                        offset: Offset(
                                          _avatarOffset.dx *
                                              (140 /
                                                  _profileEditorViewportSize),
                                          _avatarOffset.dy *
                                              (140 /
                                                  _profileEditorViewportSize),
                                        ),
                                        placeholderIcon: Icons.person,
                                        placeholderIconSize: 80,
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 6,
                                      right: 6,
                                      child: Container(
                                        width: 34,
                                        height: 34,
                                        decoration: const BoxDecoration(
                                          color: AppTheme.primary,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.edit,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            '동그란 사진 영역을 눌러 사진을 바꾸거나 위치를 조정할 수 있습니다.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 32),
                          TextField(
                            key: const ValueKey('profile_name_field'),
                            controller: _nameController,
                            textAlign: TextAlign.center,
                            decoration: InputDecoration(
                              hintText: '이름을 입력하세요',
                              hintStyle: TextStyle(
                                color: AppTheme.textDark.withValues(alpha: 0.5),
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF2F2F7),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.black.withValues(alpha: 0.1),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.black.withValues(alpha: 0.1),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Color(0xFF007AFF),
                                  width: 2,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        key: const ValueKey('profile_save_button'),
                        onPressed: _saving ? null : _saveProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF007AFF),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                '완료',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _AvatarEditResult {
  const _AvatarEditResult({required this.zoom, required this.offset});

  final double zoom;
  final Offset offset;
}

class _ProfilePhotoEditorPage extends StatefulWidget {
  const _ProfilePhotoEditorPage({
    required this.imagePath,
    required this.initialZoom,
    required this.initialOffset,
  });

  final String imagePath;
  final double initialZoom;
  final Offset initialOffset;

  @override
  State<_ProfilePhotoEditorPage> createState() =>
      _ProfilePhotoEditorPageState();
}

class _ProfilePhotoEditorPageState extends State<_ProfilePhotoEditorPage> {
  static const double _editorAvatarSize = _profileEditorViewportSize;

  double _zoom = 1.0;
  Offset _offset = Offset.zero;
  double _gestureStartZoom = 1.0;
  Offset _gestureStartOffset = Offset.zero;
  Offset _gestureStartFocalPoint = Offset.zero;

  @override
  void initState() {
    super.initState();
    _zoom = widget.initialZoom;
    _offset = ProfileAvatar.clampOffset(
      viewportSize: _editorAvatarSize,
      zoom: _zoom,
      offset: widget.initialOffset,
    );
  }

  void _updateTransform({double? zoom, Offset? offset}) {
    final nextZoom = (zoom ?? _zoom).clamp(1.0, 4.0).toDouble();
    final nextOffset = ProfileAvatar.clampOffset(
      viewportSize: _editorAvatarSize,
      zoom: nextZoom,
      offset: offset ?? _offset,
    );

    setState(() {
      _zoom = nextZoom;
      _offset = nextOffset;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundLight,
        elevation: 0,
        title: const Text(
          '프로필 사진 조정',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.textDark,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            children: [
              Expanded(
                child: Align(
                  alignment: const Alignment(0, -0.15),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '손가락으로 사진 위치를 옮기고 핀치로\n확대하세요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 44),
                      Center(
                        child: GestureDetector(
                          onScaleStart: (details) {
                            _gestureStartZoom = _zoom;
                            _gestureStartOffset = _offset;
                            _gestureStartFocalPoint = details.focalPoint;
                          },
                          onScaleUpdate: (details) {
                            final nextZoom = (_gestureStartZoom * details.scale)
                                .clamp(1.0, 4.0)
                                .toDouble();
                            final dragOffset =
                                details.focalPoint - _gestureStartFocalPoint;
                            _updateTransform(
                              zoom: nextZoom,
                              offset: _gestureStartOffset + dragOffset,
                            );
                          },
                          child: Container(
                            width: _editorAvatarSize + 16,
                            height: _editorAvatarSize + 16,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.black.withValues(alpha: 0.08),
                                width: 2,
                              ),
                            ),
                            child: ProfileAvatar(
                              size: _editorAvatarSize,
                              imagePath: widget.imagePath,
                              zoom: _zoom,
                              offset: _offset,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: const BorderSide(color: Colors.black, width: 1.5),
                      ),
                      onPressed: () {
                        _updateTransform(zoom: 1.0, offset: Offset.zero);
                      },
                      child: const Text('초기화'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(
                          context,
                        ).pop(_AvatarEditResult(zoom: _zoom, offset: _offset));
                      },
                      child: const Text('적용'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
