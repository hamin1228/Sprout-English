// FILE: lib/feature/free_talk/free_talk_page.dart
// 실시간 토큰 스트리밍 뷰 + 재연결 + 문장 버퍼링 + 자동 스크롤

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/network/server_config.dart';

class FreeTalkPage extends StatefulWidget {
  const FreeTalkPage({super.key});
  @override
  State<FreeTalkPage> createState() => _FreeTalkPageState();
}

class _FreeTalkPageState extends State<FreeTalkPage> {
  WebSocket? _ws;
  final _scrollCtrl = ScrollController();
  final _inputCtrl = TextEditingController();

  // 스트림 상태
  final List<String> _lines = [];     // 문장 단위 스냅샷
  String _tokenBuffer = '';           // 진행중 문장 버퍼
  int _lastId = 0;                    // 재연결용 resume_token
  bool _connecting = false;
  Timer? _reconnectTimer;
  int _retry = 0;

  @override
  void initState() {
    super.initState();
    _connect(initial: true);
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _ws?.close();
    _scrollCtrl.dispose();
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect({bool initial = false}) async {
    if (_connecting) return;
    _connecting = true;
    setState(() {});

    final uri = serverWebSocketUri('/ws/stream');

    try {
      final ws = await WebSocket.connect(uri.toString());
      _ws = ws;
      _retry = 0; // 성공 시 재시도 카운터 초기화

      // 첫 메시지로 resume_token 보냄
      final hello = jsonEncode({
        'type': 'hello',
        'resume_token': _lastId,
      });
      ws.add(hello);

      // 수신 루프
      unawaited(_listen(ws));
    } catch (e) {
      _scheduleReconnect();
    } finally {
      _connecting = false;
      setState(() {});
    }
  }

  Future<void> _listen(WebSocket ws) async {
    try {
      await for (final event in ws) {
        if (event is String) {
          _handleMessage(event);
        }
      }
    } catch (_) {
      // 소켓 에러/종료
    } finally {
      // 연결 끊김 → 재연결
      _scheduleReconnect();
    }
  }

  void _handleMessage(String data) {
    try {
      final obj = Map<String, dynamic>.from(jsonDecode(data) as Map);
      final type = obj['type'] as String? ?? 'delta';
      final id = (obj['id'] as num?)?.toInt() ?? 0;
      _lastId = id > _lastId ? id : _lastId;

      if (type == 'delta') {
        final role = obj['role'] as String? ?? 'assistant';
        final tok = obj['token'] as String? ?? '';
        if (role == 'assistant') {
          if (_tokenBuffer.isNotEmpty) _tokenBuffer += ' ';
          _tokenBuffer += tok;
          _notify();
        }
      } else if (type == 'user_echo') {
        final text = obj['text'] as String? ?? '';
        _commitLine("👤 $text");
      } else if (type == 'sentence_end') {
        if (_tokenBuffer.isNotEmpty) {
          _commitLine("🤖 $_tokenBuffer");
          _tokenBuffer = '';
        }
      } else if (type == 'error') {
        _commitLine("❗ ERROR: ${obj['message']}");
      }
    } catch (_) {
      // JSON 파싱 실패 등은 무시
    }
  }

  void _commitLine(String line) {
    _lines.add(line);
    _notify(scrollToEnd: true);
  }

  void _notify({bool scrollToEnd = false}) {
    if (!mounted) return;
    setState(() {});
    if (scrollToEnd) {
      // 프레임 이후 스크롤
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent + 60,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _scheduleReconnect() {
    if (!mounted) return;
    if (_reconnectTimer?.isActive ?? false) return;
    final delay = Duration(milliseconds: 400 * (1 << (_retry.clamp(0, 5))));
    _retry++;
    _commitLine("🔄 reconnect in ${delay.inMilliseconds}ms...");
    _reconnectTimer = Timer(delay, () => _connect());
  }

  Future<void> _sendText() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    _inputCtrl.clear();
    final ws = _ws;
    if (ws == null) {
      _commitLine("❗ not connected");
      return;
    }
    ws.add(jsonEncode({"type": "user_text", "text": text}));
  }

  @override
  Widget build(BuildContext context) {
    final connected = _ws != null && _ws!.readyState == WebSocket.open;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Free Talk (WS Demo)'),
        actions: [
          Icon(
            connected ? Icons.wifi : Icons.wifi_off,
            color: connected ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          if (_tokenBuffer.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.black12,
              child: Text(
                _tokenBuffer,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              itemCount: _lines.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(
                  _lines[i],
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Type text (fallback to voice)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _sendText(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _sendText,
                  child: const Text('Send'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// unawaited helper
void unawaited(Future<void> f) {}
