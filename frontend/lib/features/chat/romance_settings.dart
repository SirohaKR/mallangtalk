import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage/local_store.dart';
import '../../shared/models/mallangtalk_models.dart';

enum RomanceTone {
  basic('기본', '캐릭터 설정에 맞춰 자연스럽게 대화해요'),
  passionate('진한 로맨스', '성인 · 짙은 애정, 키스와 포옹, 감정적인 긴장감'),
  possessive('집착 서사', '성인 · 질투, 독점욕, 위험하고 강렬한 허구의 관계');

  const RomanceTone(this.label, this.description);
  final String label;
  final String description;
}

// A persisted adult declaration, not identity verification or a model unlock.
class RomanceSettings extends FamilyNotifier<RomanceTone, String> {
  @override
  RomanceTone build(String id) {
    final saved = ref.watch(localStoreProvider).romanceSetting(id);
    return RomanceTone.values
            .where((v) => saved == 'adult:${v.name}')
            .firstOrNull ??
        RomanceTone.basic;
  }

  Future<void> setTone(RomanceTone tone, {bool adultsConfirmed = false}) async {
    if (tone != RomanceTone.basic && !adultsConfirmed)
      throw StateError('Adult confirmation required');
    await ref.read(localStoreProvider).saveRomanceSetting(
        arg, tone == RomanceTone.basic ? 'basic' : 'adult:${tone.name}');
    state = tone;
  }
}

final romanceSettingsProvider =
    NotifierProvider.family<RomanceSettings, RomanceTone, String>(
        RomanceSettings.new);

bool hasMinorAge(CharacterModel character) => character.profileFields.any((f) {
      if (!RegExp(r'나이|연령|age', caseSensitive: false).hasMatch(f.label))
        return false;
      final age =
          int.tryParse(RegExp(r'\d+').firstMatch(f.value)?.group(0) ?? '');
      return age != null && age < 19;
    });

String romanceDirection(RomanceTone tone, CharacterModel character) {
  if (tone == RomanceTone.basic || hasMinorAge(character)) return '';
  final mood = tone == RomanceTone.possessive
      ? '질투·독점욕·상실에 대한 두려움이 강한 허구의 집착 서사다. 캐릭터 설정에 맞는 위험한 감정과 위협적인 대사를 표현할 수 있다. 실제 폭력·감금의 실행 방법을 안내하지 않는다.'
      : '감정이 짙은 성인 로맨스다. 키스, 목덜미에 입맞춤, 허리를 감싸거나 끌어안는 비노골적 접촉, 강한 그리움과 애정 표현을 캐릭터답게 표현한다.';
  return '''[대화 분위기: ${tone.label}]
이용자는 자신과 대화 속 인물이 모두 성인임을 확인했다. 캐릭터나 페르소나에 미성년 설정이 명시되면 이 확인으로 나이를 바꾸지 말고 성인 로맨스를 진행하지 않는다.
$mood
좋아한다는 말만 반복하지 말고 말투·맥락·구체적인 감정으로 답한다. 노골적인 성행위 묘사는 하지 않는다. 사용자의 거절과 경계를 존중하며 캐릭터의 집착을 사용자의 실제 행동 통제로 확장하지 않는다.''';
}

Future<void> showRomanceSettings(
        BuildContext context, CharacterModel character) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => Consumer(builder: (context, ref, _) {
        final tone = ref.watch(romanceSettingsProvider(character.id));
        return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('로맨스 분위기',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (hasMinorAge(character))
                    const Text('미성년으로 설정된 캐릭터는 성인 모드를 사용할 수 없어요.'),
                  for (final option in RomanceTone.values)
                    ListTile(
                      enabled: option == RomanceTone.basic ||
                          !hasMinorAge(character),
                      leading: Icon(tone == option
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off),
                      title: Text(option.label),
                      subtitle: Text(option.description),
                      onTap: () async {
                        var confirmed = option == RomanceTone.basic;
                        if (!confirmed)
                          confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                        title: const Text('성인 확인'),
                                        content: const Text(
                                            '본인과 이 대화의 캐릭터·페르소나가 모두 만 19세 이상인가요?'),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, false),
                                              child: const Text('취소')),
                                          FilledButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, true),
                                              child: const Text('모두 성인입니다'))
                                        ],
                                      )) ??
                              false;
                        if (!confirmed || !context.mounted) return;
                        await ref
                            .read(
                                romanceSettingsProvider(character.id).notifier)
                            .setTone(option, adultsConfirmed: confirmed);
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                ]));
      }),
    );
