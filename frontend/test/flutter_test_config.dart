import 'dart:async';

import 'package:mallangtalk/features/help/help_guide.dart';

/// 모든 테스트 공통 설정: 처음 사용자 안내가 저절로 떠서 다른 테스트를 가리지 않게 꺼 둠
/// (안내 자체는 help_guide_test.dart에서 켜고 확인)
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  HelpGuide.autoShow = false;
  await testMain();
}
