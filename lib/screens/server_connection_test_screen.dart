import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'theme.dart';

class ServerConnectionTestScreen extends StatefulWidget {
  const ServerConnectionTestScreen({super.key});

  @override
  State<ServerConnectionTestScreen> createState() =>
      _ServerConnectionTestScreenState();
}

enum _Status { idle, loading, success, failure }

class _ServerConnectionTestScreenState
    extends State<ServerConnectionTestScreen> {
  _Status _status = _Status.idle;
  String _message = '';
  String _detail = '';

  Future<void> _test() async {
    setState(() {
      _status = _Status.loading;
      _message = '';
      _detail = '';
    });

    final url = Uri.parse('$apiBaseUrl/api/health');
    debugPrint('[health] GET $url');

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      debugPrint('[health] ${response.statusCode} ${response.body}');

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          _status = _Status.success;
          _message = body['message'] as String? ?? '서버 연결 성공';
          _detail = 'time: ${body['time'] ?? ''}';
        });
      } else {
        setState(() {
          _status = _Status.failure;
          _message = '서버 연결 실패';
          _detail = 'status ${response.statusCode}: ${response.body}';
        });
      }
    } catch (e) {
      debugPrint('[health] error: $e');
      setState(() {
        _status = _Status.failure;
        _message = '서버 연결 실패';
        _detail = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundLight,
        elevation: 0,
        title: const Text(
          '서버 연결 테스트',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.textDark,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.borderLight),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '대상 서버',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$apiBaseUrl/api/health',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.textDark,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _status == _Status.loading ? null : _test,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: _status == _Status.loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        '서버 연결 테스트',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
            if (_status != _Status.idle) ...[
              const SizedBox(height: 32),
              _ResultCard(status: _status, message: _message, detail: _detail),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.status,
    required this.message,
    required this.detail,
  });

  final _Status status;
  final String message;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final isSuccess = status == _Status.success;
    final color = isSuccess ? const Color(0xFF2D9E6B) : const Color(0xFFD14343);
    final bgColor =
        isSuccess ? const Color(0xFFECF8F2) : const Color(0xFFFDF0F0);
    final icon = isSuccess ? Icons.check_circle_rounded : Icons.error_rounded;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 10),
              Text(
                message,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              detail,
              style: TextStyle(
                fontSize: 13,
                color: color.withValues(alpha: 0.8),
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
