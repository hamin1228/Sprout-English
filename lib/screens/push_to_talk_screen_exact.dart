import 'package:flutter/material.dart';
import 'theme.dart';

/// Push-to-Talk 전용 화면 - HTML 디자인 완전 복제
/// 심플한 레이아웃 + "Listening..." + 이중 링 마이크 버튼
class PushToTalkScreenExact extends StatelessWidget {
  const PushToTalkScreenExact({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundLight,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppTheme.textSecondary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            
            // 메인 텍스트
            const Text(
              'Listening...',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 16),
            
            // 부제
            const Text(
              'Tap and hold to speak',
              style: TextStyle(
                fontSize: 16,
                color: AppTheme.textSecondary,
              ),
            ),
            
            const Spacer(),
            
            // 이중 링 마이크 버튼
            _buildMicrophoneButton(),
            
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildMicrophoneButton() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // 외부 링
        Container(
          width: 128,
          height: 128,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.primary.withOpacity(0.2),
          ),
        ),
        
        // 중간 링
        Container(
          width: 104,
          height: 104,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.primary.withOpacity(0.2),
          ),
        ),
        
        // 마이크 버튼
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.primary,
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withOpacity(0.3),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: const Icon(
            Icons.mic,
            color: Colors.white,
            size: 36,
          ),
        ),
      ],
    );
  }
}
