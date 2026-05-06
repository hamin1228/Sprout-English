import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

class TodaysExpression {
  const TodaysExpression({required this.expression, required this.meaning});

  final String expression;
  final String meaning;

  factory TodaysExpression.fromJson(Map<String, dynamic> json) {
    return TodaysExpression(
      expression: json['expression'] as String? ?? '',
      meaning: json['meaning_ko'] as String? ?? '',
    );
  }
}

class TodaysExpressionRepository {
  static const _assetPath = 'server/dictionaries/todays_expressions.json';
  static TodaysExpression? _cached;

  static Future<TodaysExpression> loadRandomForRun() async {
    if (_cached != null) return _cached!;

    final raw = await rootBundle.loadString(_assetPath);
    final decoded = jsonDecode(raw) as List<dynamic>;

    if (decoded.isEmpty) {
      _cached = const TodaysExpression(
        expression: 'No expression available.',
        meaning: '표현 데이터가 비어 있습니다.',
      );
      return _cached!;
    }

    final randomItem =
        decoded[Random().nextInt(decoded.length)] as Map<String, dynamic>;
    _cached = TodaysExpression.fromJson(randomItem);
    return _cached!;
  }
}
