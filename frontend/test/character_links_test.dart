import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/core/storage/local_store.dart';
import 'package:mallangtalk/core/theme/app_theme.dart';
import 'package:mallangtalk/features/library/character_library.dart';
import 'package:mallangtalk/features/relations/relation_map_screen.dart';
import 'package:mallangtalk/features/studio/scenario_draft.dart';
import 'package:mallangtalk/shared/models/mallangtalk_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  test('작가 코멘트와 내 캐릭터 연결은 저장했다 다시 열어도 남아 있음', () {
    final bundle = loadSampleBundle();
    final draft = ScenarioDraft.fromBundle(bundle)
      ..authorComment = '공연 이벤트는 꼭 가 보세요'
      ..cast.add(CastDraft(name: '서이준', role: '선배', characterId: 'char_seo'));
    final saved = draft.toBundle();
    final reopened = ScenarioDraft.fromBundle(saved);

    expect(saved.character.authorComment, '공연 이벤트는 꼭 가 보세요');
    expect(saved.character.toJson()['author_comment'], '공연 이벤트는 꼭 가 보세요');
    expect(reopened.authorComment, '공연 이벤트는 꼭 가 보세요');
    expect(reopened.cast.last.characterId, 'char_seo');
    expect(reopened.cast.where((c) => c.characterId == null), isNotEmpty);
  });

  testWidgets('관계도: 내가 만든 두 캐릭터를 이으면 주변 인물에 연결되어 저장됨', (tester) async {
    final base = loadSampleBundle();
    ScenarioBundle made(String id, String name) => base.copyWithCharacter(
        CharacterModel.fromJson({...base.character.toJson(), 'id': id, 'name': name, 'extra_cast': []}));
    final a = made('char_a', '하린');
    final b = made('char_b', '서준');
    SharedPreferences.setMockInitialValues({
      'library_v1': jsonEncode([
        for (final bundle in [a, b])
          {'id': bundle.character.id, 'source': 'created', 'added_at': '2026-10-22T00:00:00', 'bundle': bundle.toJson()},
      ]),
    });
    await tester.binding.setSurfaceSize(const Size(420, 900));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        builtinBundlesProvider.overrideWith((ref) async => [base]),
        sharedPreferencesProvider.overrideWith((ref) => SharedPreferences.getInstance()),
      ],
      child: MaterialApp(theme: AppTheme.lightTheme, home: const _Ready(child: RelationMapScreen())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('아직 이어 둔 관계가 없어요'), findsOneWidget);

    await tester.tap(find.text('관계 잇기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '소꿉친구');
    await tester.tap(find.text('잇기'));
    await tester.pumpAndSettle();

    expect(find.text('관계 1'), findsOneWidget);
    final container = ProviderScope.containerOf(tester.element(find.byType(RelationMapScreen)));
    final cast = container.read(characterLibraryProvider.notifier).byId('char_a')!.bundle.character.extraCast.last;
    expect(cast.characterId, 'char_b');
    expect(cast.name, '서준');
    expect(cast.role, '소꿉친구');
  });
}

/// 저장소와 기본 캐릭터가 준비된 뒤에 화면을 띄움
class _Ready extends ConsumerWidget {
  const _Ready({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = ref.watch(builtinBundlesProvider).hasValue && ref.watch(sharedPreferencesProvider).hasValue;
    return ready ? child : const SizedBox();
  }
}
