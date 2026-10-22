import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/features/studio/scenario_draft.dart';

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
}
