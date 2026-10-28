import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/app.dart';
import 'package:mallangtalk/core/router/app_router.dart';
import 'package:mallangtalk/core/storage/local_store.dart';
import 'package:mallangtalk/features/chat/chat_notifier.dart';
import 'package:mallangtalk/features/chat/chat_screen.dart';
import 'package:mallangtalk/features/library/character_library.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'test_helpers.dart';

void main() {
  testWidgets(
      'desktop room selection is in the URL and survives app recreation',
      (tester) async {
    final room = freeRoomId(dohaId);
    SharedPreferences.setMockInitialValues({
      ...fastTempo,
      'chat_rooms_v1': [room]
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => appRouter.go('/discover'));
    Future<void> boot() async {
      await tester.pumpWidget(ProviderScope(
          key: UniqueKey(),
          overrides: [
            builtinBundlesProvider
                .overrideWith((ref) async => [loadSampleBundle()]),
            sharedPreferencesProvider
                .overrideWith((ref) => SharedPreferences.getInstance()),
            clockProvider.overrideWithValue(testNow),
          ],
          child: const MallangTalkApp()));
      await settle(tester);
    }

    appRouter.go('/chats');
    await boot();
    appRouter.go('/chats');
    await settle(tester);
    expect(find.byType(ChatScreen), findsNothing);
    await tester.tap(find.text(loadSampleBundle().character.name).first);
    await settle(tester);
    expect(appRouter.routeInformationProvider.value.uri.queryParameters['room'],
        room);
    expect(tester.widget<ChatScreen>(find.byType(ChatScreen)).roomId, room);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await boot();
    expect(tester.widget<ChatScreen>(find.byType(ChatScreen)).roomId, room);
    tester.view.physicalSize = const Size(420, 900);
    await tester.binding.setSurfaceSize(const Size(420, 900));
    await settle(tester);
    expect(tester.widget<ChatScreen>(find.byType(ChatScreen)).roomId, room);
  });
}
