// FILE: lib/feature/writing/utils/diff_utils.dart
import 'package:flutter/material.dart';

enum Op { equal, insert, delete }

class DiffOp {
  final Op op;
  final List<String> tokens; // 토큰(단어/공백)을 그대로 보관
  DiffOp(this.op, this.tokens);
}

class DiffResult {
  final List<DiffOp> ops;
  DiffResult(this.ops);

  int get added =>
      ops.where((o) => o.op == Op.insert).fold(0, (a, b) => a + b.tokens.length);
  int get removed =>
      ops.where((o) => o.op == Op.delete).fold(0, (a, b) => a + b.tokens.length);
  int get kept =>
      ops.where((o) => o.op == Op.equal).fold(0, (a, b) => a + b.tokens.length);

  String statsString() =>
      '추가: $added · 삭제: $removed · 유지: $kept (토큰 기준)';

  TextSpan toTextSpan(BuildContext context) {
    final addStyle = TextStyle(
      decoration: TextDecoration.underline,
      decorationThickness: 2,
      decorationStyle: TextDecorationStyle.solid,
      backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
    );
    final delStyle = TextStyle(
      decoration: TextDecoration.lineThrough,
      decorationThickness: 2,
      color: Theme.of(context).colorScheme.error,
      backgroundColor: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.25),
    );
    final keepStyle = const TextStyle();

    final children = <InlineSpan>[];
    for (final op in ops) {
      final text = op.tokens.join();
      switch (op.op) {
        case Op.equal:
          children.add(TextSpan(text: text, style: keepStyle));
          break;
        case Op.insert:
          children.add(TextSpan(text: text, style: addStyle));
          break;
        case Op.delete:
          children.add(TextSpan(text: text, style: delStyle));
          break;
      }
    }
    return TextSpan(children: children);
  }
}

class DiffEngine {
  /// preserveSpaces=true이면 공백/줄바꿈을 별도 토큰으로 유지해 원문 레이아웃을 살립니다.
  static DiffResult compare({
    required String original,
    required String revised,
    bool preserveSpaces = true,
  }) {
    final a = _tokenize(original, preserveSpaces: preserveSpaces);
    final b = _tokenize(revised, preserveSpaces: preserveSpaces);

    // LCS 테이블 구축
    final m = a.length, n = b.length;
    final dp = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));
    for (var i = m - 1; i >= 0; i--) {
      for (var j = n - 1; j >= 0; j--) {
        if (a[i] == b[j]) {
          dp[i][j] = dp[i + 1][j + 1] + 1;
        } else {
          dp[i][j] = (dp[i + 1][j] >= dp[i][j + 1]) ? dp[i + 1][j] : dp[i][j + 1];
        }
      }
    }

    // 역추적 → equal/insert/delete 시퀀스
    final ops = <DiffOp>[];
    int i = 0, j = 0;
    while (i < m && j < n) {
      if (a[i] == b[j]) {
        _push(ops, Op.equal, a[i]);
        i++; j++;
      } else if (dp[i + 1][j] >= dp[i][j + 1]) {
        _push(ops, Op.delete, a[i]);
        i++;
      } else {
        _push(ops, Op.insert, b[j]);
        j++;
      }
    }
    while (i < m) { _push(ops, Op.delete, a[i]); i++; }
    while (j < n) { _push(ops, Op.insert, b[j]); j++; }

    return DiffResult(ops);
  }

  static void _push(List<DiffOp> ops, Op kind, String token) {
    if (ops.isNotEmpty && ops.last.op == kind) {
      ops.last.tokens.add(token);
    } else {
      ops.add(DiffOp(kind, [token]));
    }
  }

  /// 단어/구두점/공백을 분리해 **사람이 읽는 레이아웃 보존**을 시도합니다.
  static List<String> _tokenize(String s, {required bool preserveSpaces}) {
    if (!preserveSpaces) {
      // 단순 단어 기반(공백은 무시) — 통계에만 유용
      final words = RegExp(r"[A-Za-z']+|[0-9]+|[^\sA-Za-z0-9]")
          .allMatches(s)
          .map((m) => m.group(0)!)
          .toList();
      return words;
    }

    // 공백/줄바꿈을 별도 토큰으로 유지
    final regex = RegExp(r"([A-Za-z']+|[0-9]+|[^\sA-Za-z0-9]|[\s]+)");
    final tokens = <String>[];
    for (final m in regex.allMatches(s)) {
      tokens.add(m.group(0)!);
    }
    return tokens;
  }
}



