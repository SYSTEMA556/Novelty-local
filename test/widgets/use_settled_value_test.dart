import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/screens/local_library_view.dart';

class _Probe extends HookWidget {
  const _Probe({required this.value, required this.immediate});

  final String value;
  final bool immediate;

  @override
  Widget build(BuildContext context) {
    final shown = useSettledValue(
      value,
      const Duration(milliseconds: 300),
      immediateWhen: immediate,
    );
    return Text(shown, textDirection: TextDirection.ltr);
  }
}

void main() {
  testWidgets('変化が落ち着くまで前の値を返す', (tester) async {
    await tester.pumpWidget(const _Probe(value: 'a', immediate: false));
    expect(find.text('a'), findsOneWidget);

    await tester.pumpWidget(const _Probe(value: 'b', immediate: false));
    expect(find.text('a'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const _Probe(value: 'c', immediate: false));
    await tester.pump(const Duration(milliseconds: 200));
    // 「b」は待っている間に「c」に替わったので出ない
    expect(find.text('a'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('c'), findsOneWidget);
  });

  testWidgets('すぐ返す指定なら待たない', (tester) async {
    await tester.pumpWidget(const _Probe(value: 'a', immediate: false));
    await tester.pumpWidget(const _Probe(value: '', immediate: true));
    expect(find.text(''), findsOneWidget);
  });
}
