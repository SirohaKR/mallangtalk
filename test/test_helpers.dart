import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/core/storage/local_store.dart';
import 'package:mallangtalk/features/chat/chat_notifier.dart';
import 'package:mallangtalk/features/chat/chat_screen.dart';

/// 앱의 로딩 문지기와 같은 역할: 시나리오와 저장소가 준비되면 채팅방을 띄움
class BootGate extends ConsumerWidget {
  const BootGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = ref.watch(scenarioBundleProvider).hasValue &&
        ref.watch(sharedPreferencesProvider).hasValue;
    return ready ? const ChatScreen() : const Scaffold(body: SizedBox());
  }
}

/// 타자 연출 타이머를 충분히 흘려보냄
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

Future<void> choose(WidgetTester tester, String label) async {
  final button = find.widgetWithText(ElevatedButton, label);
  expect(button, findsOneWidget, reason: '선택지 "$label"이 보여야 함');
  await tester.tap(button);
  await settle(tester);
}

Future<void> closeCutscene(WidgetTester tester) async {
  await tester.tap(find.textContaining('화면을 탭하면 계속'));
  await settle(tester);
}
