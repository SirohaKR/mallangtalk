import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/app.dart';
import 'package:mallangtalk/core/storage/local_store.dart';
import 'package:mallangtalk/features/chat/chat_notifier.dart';
import 'package:mallangtalk/features/chat/chat_screen.dart';
import 'package:mallangtalk/features/library/character_library.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// 하단 탭(내 캐릭터 / 채팅 / 캐릭터 추가 / 설정)이 있는 실제 앱 화면 흐름 테스트입니다.
void main() {
  testWidgets('채팅 탭에서 안 읽은 톡을 보고, 대화방에 들어가면 읽음 처리', (tester) async {
    SharedPreferences.setMockInitialValues({...fastTempo});
    await tester.binding.setSurfaceSize(const Size(420, 900));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        builtinBundlesProvider.overrideWith((ref) async => [loadSampleBundle()]),
        sharedPreferencesProvider.overrideWith((ref) => SharedPreferences.getInstance()),
      ],
      child: const MallangTalkApp(),
    ));
    await settle(tester);

    // 처음 화면은 내 캐릭터 탭, 기본 캐릭터 윤도하가 있음
    expect(find.text('내 캐릭터 1'), findsOneWidget);
    expect(find.text('윤도하'), findsOneWidget);

    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    final room = container.read(chatRoomProvider(dohaId));
    // 대화방을 안 열어도 톡은 와 있고(안 읽음), 말풍선이 두 번씩 쌓이지 않음
    final texts = room.messages.where((m) => !m.isSystem).map((m) => m.text).toList();
    expect(texts.first, '야야야');
    expect(texts.toSet().length, texts.length, reason: texts.join(' / '));
    expect(room.unreadCount, texts.length);

    await tester.tap(find.text('채팅'));
    await settle(tester);
    expect(find.text('${room.unreadCount}'), findsWidgets);

    await tester.tap(find.text('윤도하'));
    await settle(tester);
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(container.read(chatRoomProvider(dohaId)).unreadCount, 0);
    expect(find.widgetWithText(ElevatedButton, '지금 바로 같이 찾으러 가겠다고 하기'), findsOneWidget);

    await tester.tap(find.byTooltip('채팅방 목록'));
    await settle(tester);
    expect(find.byType(ChatScreen), findsNothing);

    await tester.tap(find.text('캐릭터 추가'));
    await settle(tester);
    expect(find.text('받아오기'), findsOneWidget);
    expect(find.text('추가됨'), findsOneWidget);
  });
}
