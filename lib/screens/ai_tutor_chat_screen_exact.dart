import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/network/server_config.dart';
import '../core/statistics/learning_activity_recorder.dart';
import 'theme.dart';

/// AI 튜터 채팅 화면 - HTML 디자인 완전 복제
/// Conversation with Alex + 메시지 버블 + 실시간 피드백 + 타이핑 인디케이터
class AiTutorChatScreenExact extends StatefulWidget {
  const AiTutorChatScreenExact({super.key});

  @override
  State<AiTutorChatScreenExact> createState() => _AiTutorChatScreenExactState();
}

class ChatMessage {
  final String sender;
  final String text;
  final bool isUser;
  final bool isTyping;

  ChatMessage({
    required this.sender,
    required this.text,
    required this.isUser,
    this.isTyping = false,
  });

  ChatMessage copyWith({String? text, bool? isTyping}) {
    return ChatMessage(
      sender: sender,
      text: text ?? this.text,
      isUser: isUser,
      isTyping: isTyping ?? this.isTyping,
    );
  }
}

class _AiTutorChatScreenExactState extends State<AiTutorChatScreenExact> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  WebSocketChannel? _channel;
  final List<ChatMessage> _messages = [];
  bool _isConnected = false;
  DateTime? _sessionStartedAt;

  @override
  void initState() {
    super.initState();
    _sessionStartedAt = DateTime.now();
    _connect();
    // 초기 환영 메시지
    _messages.add(
      ChatMessage(
        sender: 'Alex',
        text: 'Hi there! Let\'s talk about your day. How was it?',
        isUser: false,
      ),
    );
  }

  void _connect() {
    try {
      _channel = WebSocketChannel.connect(serverWebSocketUri('/chat/stream'));
      _isConnected = true;

      _channel!.stream.listen(
        (message) {
          final data = jsonDecode(message);
          _handleMessage(data);
        },
        onError: (error) {
          debugPrint('WS Error: $error');
          setState(() => _isConnected = false);
        },
        onDone: () {
          debugPrint('WS Closed');
          setState(() => _isConnected = false);
        },
      );
    } catch (e) {
      debugPrint('Connection failed: $e');
      setState(() => _isConnected = false);
    }
  }

  void _handleMessage(Map<String, dynamic> data) {
    setState(() {
      switch (data['type']) {
        case 'init':
          // 세션 시작
          break;
        case 'delta':
          // 스트리밍 텍스트 업데이트
          if (_messages.isNotEmpty &&
              !_messages.last.isUser &&
              _messages.last.isTyping) {
            // 타이핑 중인 메시지를 실제 텍스트로 교체하거나 이어붙임
            // 첫 델타면 타이핑 상태 해제하고 텍스트 시작
            // 여기서는 단순화를 위해 마지막 메시지가 AI이고 타이핑 중이면 텍스트를 업데이트
            // 하지만 delta는 조각이므로 기존 텍스트에 append 해야 함
            // 초기 상태: text="" (or placeholder), isTyping=true
            // 첫 delta: text="H", isTyping=false (실제로는 계속 스트리밍 중임을 표시해야 하지만, UI상 텍스트가 보이면 typing indicator는 숨기는게 일반적)

            // 로직 수정:
            // 1. 사용자가 메시지 보냄 -> AI 메시지(isTyping=true, text="") 추가
            // 2. 첫 delta 수신 -> AI 메시지(isTyping=false, text=chunk) 업데이트
            // 3. 이후 delta 수신 -> AI 메시지(text += chunk) 업데이트

            final currentText = _messages.last.isTyping
                ? ""
                : _messages.last.text;
            _messages.last = _messages.last.copyWith(
              text: currentText + (data['text'] ?? ''),
              isTyping: false,
            );
          } else if (_messages.isNotEmpty && !_messages.last.isUser) {
            // 이미 타이핑이 끝난 상태(혹은 스트리밍 중)에서 추가 델타
            _messages.last = _messages.last.copyWith(
              text: _messages.last.text + (data['text'] ?? ''),
            );
          }
          break;
        case 'done':
          // 스트리밍 완료
          break;
        case 'error':
          _messages.add(
            ChatMessage(
              sender: 'System',
              text: 'Error: ${data['error']}',
              isUser: false,
            ),
          );
          break;
      }
    });
    _scrollToBottom();
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    if (_channel == null || !_isConnected) {
      _connect(); // 재연결 시도
      // 연결 대기 후 전송은 복잡하므로 일단 에러 표시 혹은 재시도 유도
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reconnecting to server... try again.')),
      );
      return;
    }

    setState(() {
      _messages.add(ChatMessage(sender: 'You', text: text, isUser: true));
      _messages.add(
        ChatMessage(sender: 'Alex', text: '', isUser: false, isTyping: true),
      );
      _messageController.clear();
    });
    _scrollToBottom();

    _channel!.sink.add(jsonEncode({'type': 'start', 'prompt': text}));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // 대화 영역
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                if (msg.isUser) {
                  return Column(
                    children: [
                      _buildUserMessage(msg.sender, msg.text),
                      const SizedBox(height: 16),
                    ],
                  );
                } else {
                  if (msg.isTyping && msg.text.isEmpty) {
                    return Column(
                      children: [
                        _buildTypingIndicator(),
                        const SizedBox(height: 16),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      _buildAIMessage(msg.sender, msg.text),
                      const SizedBox(height: 16),
                    ],
                  );
                }
              },
            ),
          ),

          // 입력 바
          _buildInputBar(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // 힌트 기능 (데모)
          setState(() {
            _messages.add(
              ChatMessage(
                sender: 'System',
                text: 'Tip: Try asking about "hobbies" or "travel".',
                isUser: false,
              ),
            );
          });
          _scrollToBottom();
        },
        backgroundColor: AppTheme.primary,
        child: const Icon(Icons.lightbulb, color: Colors.white),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppTheme.backgroundLight,
      elevation: 0,
      leading: Container(
        margin: const EdgeInsets.all(8),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.grey,
        ),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Conversation with Alex',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
          Text(
            _isConnected ? 'Online' : 'Offline',
            style: TextStyle(
              fontSize: 12,
              color: _isConnected ? Colors.green : Colors.red,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.help_outline, color: AppTheme.textSecondary),
          onPressed: () {},
        ),
      ],
    );
  }

  Widget _buildAIMessage(String name, String message) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // AI 아바타
        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.grey,
          ),
        ),
        const SizedBox(width: 12),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 4),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(12),
                          topRight: Radius.circular(12),
                          bottomRight: Radius.circular(12),
                        ),
                        border: Border.all(color: AppTheme.borderLight),
                      ),
                      child: Text(
                        message,
                        style: const TextStyle(
                          fontSize: 16,
                          color: AppTheme.textDark,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.volume_up, size: 20),
                    color: AppTheme.textSecondary,
                    onPressed: () {},
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUserMessage(String name, String message) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 4),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: const BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
                child: Text(
                  message,
                  style: const TextStyle(fontSize: 16, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),

        // 사용자 아바타
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.grey[300],
          ),
        ),
      ],
    );
  }

  Widget _buildTypingIndicator() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.grey,
          ),
        ),
        const SizedBox(width: 12),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.borderLight),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDot(0),
              const SizedBox(width: 4),
              _buildDot(1),
              const SizedBox(width: 4),
              _buildDot(2),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDot(int index) {
    return TweenAnimationBuilder(
      tween: Tween<double>(begin: 0.4, end: 1.0),
      duration: const Duration(milliseconds: 600),
      builder: (context, double value, child) {
        return Opacity(
          opacity: value,
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.backgroundLight,
        border: Border(top: BorderSide(color: AppTheme.borderLight)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        onSubmitted: (_) => _sendMessage(),
                        decoration: const InputDecoration(
                          hintText: 'Type or hold mic to speak...',
                          hintStyle: TextStyle(color: AppTheme.textSecondary),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.send,
                        color: AppTheme.textSecondary,
                      ),
                      onPressed: _sendMessage,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              child: IconButton(
                icon: const Icon(Icons.mic, color: Colors.white, size: 24),
                onPressed: () {},
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    final startedAt = _sessionStartedAt;
    final userTurns = _messages.where((message) => message.isUser).length;
    if (startedAt != null && userTurns > 0) {
      unawaited(
        LearningActivityRecorder.recordAiTutorChat(
          durationSec: DateTime.now().difference(startedAt).inSeconds,
          turnCount: userTurns,
        ),
      );
    }
    _messageController.dispose();
    _scrollController.dispose();
    _channel?.sink.close();
    super.dispose();
  }
}
