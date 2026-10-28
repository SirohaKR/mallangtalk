import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/shared/widgets/mallang_loading.dart';
import 'package:mallangtalk/shared/widgets/mallang_mark.dart';

void main() {
  Future<void> show(WidgetTester tester, Widget overlay) => tester.pumpWidget(
        MaterialApp(
            home: Scaffold(
                body: Stack(children: [const SizedBox.expand(child: Text('뒤 화면')), Positioned.fill(child: overlay)]))),
      );

  testWidgets('말랑이와 말풍선에 하는 일·퍼센트를 보여 줌', (tester) async {
    await show(tester, const MallangLoadingOverlay(message: '대사를 쓰는 중', progress: 0.42));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(MallangMark), findsOneWidget);
    expect(find.text('대사를 쓰는 중'), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
  });

  testWidgets('퍼센트를 모르면 숨기고, 뒤 화면은 눌리지 않음', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          Center(child: TextButton(onPressed: () => tapped = true, child: const Text('뒤 버튼'))),
          const Positioned.fill(child: MallangLoadingOverlay(message: '쓰는 중')),
        ]),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('%'), findsNothing);
    await tester.tap(find.text('뒤 버튼'), warnIfMissed: false);
    expect(tapped, isFalse);
  });
}
