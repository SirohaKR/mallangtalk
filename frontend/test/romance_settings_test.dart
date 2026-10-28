import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/features/chat/chat_notifier.dart';
import 'package:mallangtalk/features/chat/romance_settings.dart';
import 'package:mallangtalk/shared/models/mallangtalk_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'test_helpers.dart';

void main() {
  testWidgets('성인 확인 없이 모드를 켤 수 없고 확인한 설정은 재진입 후 유지', (tester) async {
    SharedPreferences.setMockInitialValues({...fastTempo});
    final room = freeRoomId(dohaId);
    final container = await openDohaChat(tester, roomId: room);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = romanceSettingsProvider(dohaId);
    expect(container.read(provider), RomanceTone.basic);
    await expectLater(
        container.read(provider.notifier).setTone(RomanceTone.passionate),
        throwsStateError);
    await container
        .read(provider.notifier)
        .setTone(RomanceTone.possessive, adultsConfirmed: true);
    final reopened = await openDohaChat(tester, roomId: room);
    expect(reopened.read(provider), RomanceTone.possessive);
  });
  test('진한 로맨스와 허구의 집착 방향을 구분하고 미성년 설정은 제외', () {
    final character = loadSampleBundle().character;
    expect(romanceDirection(RomanceTone.passionate, character), contains('키스'));
    expect(romanceDirection(RomanceTone.possessive, character),
        contains('허구의 집착 서사'));
    expect(romanceDirection(RomanceTone.basic, character), isEmpty);
    final minor = CharacterModel.fromJson({
      ...character.toJson(),
      'profile_fields': [const ProfileField(label: '나이', value: '17세').toJson()]
    });
    expect(hasMinorAge(minor), isTrue);
    expect(romanceDirection(RomanceTone.passionate, minor), isEmpty);
  });
}
