import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/client.dart';

class HealthzPage extends ConsumerStatefulWidget {
  const HealthzPage({super.key});

  @override
  ConsumerState<HealthzPage> createState() => _HealthzPageState();
}

class _HealthzPageState extends ConsumerState<HealthzPage> {
  String _res = '요청 전';

  @override
  void initState() {
    super.initState();
    _ping();
  }

  Future<void> _ping() async {
    final Dio dio = ref.read(dioProvider);
    setState(() {
      _res = '요청 중...';
    });
    try {
      final r = await dio.get('/healthz');
      setState(() {
        _res = r.data.toString();
      });
    } catch (e) {
      setState(() {
        _res = '실패: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Healthz')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_res),
        ),
      ),
    );
  }
}
