import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/app.dart';
import 'package:mallangtalk/core/network/mallangtalk_api.dart';
import 'package:mallangtalk/core/network/server_info.dart';
import 'package:mallangtalk/core/router/app_router.dart';
import 'package:mallangtalk/core/storage/local_store.dart';
import 'package:mallangtalk/features/auth/auth_state.dart';
import 'package:mallangtalk/features/chat/chat_notifier.dart';
import 'package:mallangtalk/features/library/character_library.dart';
import 'package:mallangtalk/shared/models/mallangtalk_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// 서버 대신 메모리에 계정·캐릭터를 두는 가짜 API
class _FakeServer {
  final saved = <String, ScenarioBundle>{};
  final deleted = <String>[];
  final published = <ServerCharacter>[];
  /// 기기 연동 저장값 (로그인 표마다 = 계정마다)
  final state = <String, Map<String, SyncedValue>>{};
}

class _FakeApi extends MallangtalkApi {
  _FakeApi(this.server, String? token) : super(baseUrl: 'http://nas.local:5200', token: token);
  final _FakeServer server;

  @override
  Future<(String, AccountUser)> login(String username, String password) async {
    if (password != 'mallang123') throw const ApiException('아이디나 비밀번호가 맞지 않아요.');
    return ('token-1', AccountUser(username: username, nickname: '쨋뀨'));
  }

  @override
  Future<void> logout() async {}

  @override
  Future<List<ServerCharacter>> myCharacters() async =>
      [for (final b in server.saved.values) ServerCharacter(bundle: b, creator: '쨋뀨', mine: true)];

  @override
  Future<List<ServerCharacter>> publishedCharacters() async => server.published;

  @override
  Future<ScenarioBundle> saveCharacter(ScenarioBundle bundle, {bool published = true}) async {
    // 진짜 서버처럼 사진을 주소로 바꿔서 돌려줌
    final moved = ScenarioBundle(
      character: bundle.character,
      events: bundle.events,
      nodes: bundle.nodes,
      images: {for (final key in bundle.images.keys) key: '/api/images/$key'},
    );
    server.saved[bundle.character.id] = moved;
    return moved;
  }

  @override
  Future<void> deleteCharacter(String id) async => server.deleted.add(id);

  @override
  Future<Map<String, SyncedValue>> myState() async => {...?server.state[token]};

  @override
  Future<void> saveMyState(Map<String, SyncedValue> items) async {
    final mine = server.state.putIfAbsent(token!, () => {});
    for (final MapEntry(:key, :value) in items.entries) {
      // 진짜 서버처럼 더 나중에 바뀐 값만 남김
      if ((mine[key]?.updatedAt ?? -1) <= value.updatedAt) mine[key] = value;
    }
  }
}

void main() {
  late _FakeServer server;

  Future<ProviderContainer> openApp(WidgetTester tester) async {
    appRouter.go('/friends');
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [
        builtinBundlesProvider.overrideWith((ref) async => [loadSampleBundle()]),
        sharedPreferencesProvider.overrideWith((ref) => SharedPreferences.getInstance()),
        clockProvider.overrideWithValue(testNow),
        serverInfoProvider.overrideWith((ref) async =>
            const ServerInfo(baseUrl: 'http://nas.local:5200', providers: {}, accounts: true)),
        apiFactoryProvider.overrideWithValue((base, token) => _FakeApi(server, token)),
      ],
      child: const MallangTalkApp(),
    ));
    await settle(tester);
    return ProviderScope.containerOf(tester.element(find.byType(MallangTalkApp)));
  }

  setUp(() => server = _FakeServer());

  testWidgets('서버에서 열면 로그인부터: 틀리면 안내, 맞으면 앱으로, 로그아웃하면 다시 로그인 화면', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await openApp(tester);
    expect(find.widgetWithText(ElevatedButton, '로그인'), findsOneWidget);

    await tester.tap(find.text('계정이 없나요? 회원가입'));
    await settle(tester);
    expect(find.widgetWithText(TextField, '비밀번호 확인'), findsOneWidget);
    await tester.tap(find.text('이미 계정이 있어요 · 로그인'));
    await settle(tester);

    await tester.enterText(find.widgetWithText(TextField, '아이디'), 'jjaet');
    await tester.enterText(find.widgetWithText(TextField, '비밀번호'), 'wrong-pass');
    await tester.tap(find.widgetWithText(ElevatedButton, '로그인'));
    await settle(tester);
    expect(find.text('아이디나 비밀번호가 맞지 않아요.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '비밀번호'), 'mallang123');
    await tester.tap(find.widgetWithText(ElevatedButton, '로그인'));
    await settle(tester);
    expect(find.widgetWithText(ElevatedButton, '로그인'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('auth_token'), 'token-1');

    // 새로고침해도 로그인 유지
    await openApp(tester);
    expect(find.widgetWithText(ElevatedButton, '로그인'), findsNothing);

    appRouter.go('/settings');
    await settle(tester);
    expect(find.text('jjaet 계정으로 로그인'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings_ai')));
    await settle(tester);
    expect(find.text('Gemini 키 받으러 가기'), findsOneWidget); // 처음이면 Gemini가 기본
    appRouter.go('/settings/account');
    await settle(tester);
    expect(find.text('쨋뀨 (jjaet)'), findsOneWidget);
    await tester.tap(find.text('로그아웃'));
    await settle(tester);
    expect(find.widgetWithText(ElevatedButton, '로그인'), findsOneWidget);
    expect(prefs.getString('auth_token'), isNull);
  });

  testWidgets('로그인하면 내가 만든 캐릭터를 서버에 올리고, 받아오기에 다른 유저 캐릭터가 보임', (tester) async {
    final mine = ScenarioBundle(
      character: loadSampleBundle().character.copyWith(id: 'char_mine', tagline: '내가 만든 캐릭터'),
      events: const [],
      nodes: const {},
      images: const {'p1': 'data:image/jpeg;base64,AAAA'},
    );
    SharedPreferences.setMockInitialValues({
      'auth_token': 'token-1',
      'auth_user': '{"username":"jjaet","nickname":"쨋뀨"}',
    });
    server.published.add(ServerCharacter(
      bundle: ScenarioBundle(
        character: loadSampleBundle().character.copyWith(id: 'char_other', tagline: '다른 유저가 만든 캐릭터'),
        events: const [],
        nodes: const {},
      ),
      creator: '다른유저',
      mine: false,
    ));
    final container = await openApp(tester);
    final library = container.read(characterLibraryProvider.notifier);
    await library.add(mine, CharacterSource.created);
    await settle(tester);

    // 서버에 올라가고, 브라우저에는 사진 대신 주소만 남음
    expect(server.saved['char_mine']?.character.tagline, '내가 만든 캐릭터');
    expect(library.byId('char_mine')!.bundle.images['p1'], '/api/images/p1');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('library_v1') ?? prefs.getKeys().join(), isNot(contains('base64')));

    appRouter.go('/discover');
    await settle(tester);
    expect(find.text('다른 유저가 만든 캐릭터'), findsWidgets);
    expect(find.text('다른유저'), findsWidgets); // 카드마다 만든 사람
    appRouter.go('/creator/${Uri.encodeComponent('다른유저')}');
    await settle(tester);
    expect(find.text('만든 말랑이 1 · 받은 친구 추가 0'), findsOneWidget);

    await library.remove('char_mine');
    expect(server.deleted, ['char_mine']);
  });

  testWidgets('같은 계정이면 PC와 폰이 내 프로필·즐겨찾기·앨범을 같이 씀, 다른 계정이면 안 섞임', (tester) async {
    const login = {'auth_token': 'token-1', 'auth_user': '{"username":"jjaet","nickname":"쨋뀨"}'};
    // PC: 연동 기능 전부터 쓰던 값이 있음 → 로그인하면 서버로 올라감
    SharedPreferences.setMockInitialValues({
      ...login,
      'my_profile': '{"nickname":"쨋뀨","intro":"PC에서 정함"}',
      'album_$dohaId': ['e1', 'e2'],
      'byok_key_gemini': 'my-secret-key',
    });
    var container = await openApp(tester);
    expect(server.state['token-1']?['my_profile']?.value, contains('PC에서 정함'));
    expect(server.state['token-1']?['album_$dohaId']?.value, ['e1', 'e2']);
    expect(server.state['token-1']?.keys, isNot(contains('byok_key_gemini'))); // AI 키는 안 올림

    await container.read(favoritesProvider.notifier).toggle(dohaId);
    await settle(tester);
    expect(server.state['token-1']?['favorites_v1']?.value, [dohaId]);

    // 폰: 처음 열면 서버 값을 받아서 같은 화면
    SharedPreferences.setMockInitialValues(login);
    container = await openApp(tester);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('my_profile'), contains('PC에서 정함'));
    expect(prefs.getStringList('album_$dohaId'), ['e1', 'e2']);
    expect(container.read(favoritesProvider), {dohaId});
    expect(find.text('즐겨찾기 1'), findsOneWidget);

    // 폰에서 앨범이 늘면 서버에도 (PC는 다음에 열 때 받음)
    await container.read(localStoreProvider).saveAlbum(dohaId, ['e1', 'e2', 'e3']);
    await settle(tester);
    expect(server.state['token-1']?['album_$dohaId']?.value, ['e1', 'e2', 'e3']);

    // 같은 폰에서 다른 계정으로 로그인하면 이전 계정 값은 지움
    SharedPreferences.setMockInitialValues({
      ...Map.fromEntries(prefs.getKeys().map((k) => MapEntry(k, prefs.get(k)!))),
      'auth_token': 'token-2',
      'auth_user': '{"username":"friend","nickname":"친구"}',
    });
    container = await openApp(tester);
    final after = await SharedPreferences.getInstance();
    expect(after.getString('my_profile'), isNull);
    expect(after.getStringList('album_$dohaId'), isNull);
    expect(container.read(favoritesProvider), isEmpty);
    expect(server.state['token-1']?['album_$dohaId']?.value, ['e1', 'e2', 'e3']); // 원래 계정 값은 그대로
  });
}
