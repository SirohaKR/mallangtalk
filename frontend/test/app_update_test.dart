import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/core/update/app_update.dart';

/// 새 버전 자동 업데이트: 켤 때·돌아올 때는 바로 새로고침, 보는 중엔 안내만
void main() {
  Future<void> leaveAndComeBack(WidgetTester tester) async {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
  }

  Widget app({
    required String current,
    required String? Function() server,
    required VoidCallback onReload,
    List<String>? log,
  }) {
    return MaterialApp(
      builder: (context, child) => AppUpdateWatcher(
        currentBuild: current,
        fetchBuild: () async => server(),
        reload: onReload,
        beforeReload: () async => log?.add('flush'),
        child: child!,
      ),
      home: const Scaffold(body: Text('홈')),
    );
  }

  testWidgets('켤 때 서버에 새 버전이 있으면 미리 보낼 걸 보내고 바로 새로고침', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(app(current: 'start-1', server: () => 'start-2', onReload: () => log.add('reload'), log: log));
    await tester.pump();
    expect(log, ['flush', 'reload']);
  });

  testWidgets('같은 버전이면 아무 일 없음, 빌드 번호가 없으면(개발 중) 확인도 안 함', (tester) async {
    var reloads = 0, asked = 0;
    await tester.pumpWidget(app(current: 'same-1', server: () => 'same-1', onReload: () => reloads++));
    await tester.pump();
    await leaveAndComeBack(tester);
    expect(reloads, 0);
    expect(find.text('새 버전이 나왔어요'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(current: '', server: () { asked++; return 'x'; }, onReload: () => reloads++));
    await tester.pump();
    await leaveAndComeBack(tester);
    expect(asked, 0);
    expect(reloads, 0);
  });

  testWidgets('보는 중에 새 버전이 나오면 안내만 띄우고, 다른 앱에 갔다 오면 새로고침', (tester) async {
    var server = 'live-1';
    var reloads = 0;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => AppUpdateWatcher(
        currentBuild: 'live-1',
        fetchBuild: () async => server,
        reload: () => reloads++,
        checkEvery: const Duration(minutes: 1),
        child: child!,
      ),
      home: const Scaffold(body: Text('홈')),
    ));
    await tester.pump();
    expect(find.text('새 버전이 나왔어요'), findsNothing);

    server = 'live-2';
    await tester.pump(const Duration(minutes: 1));
    await tester.pump();
    expect(find.text('새 버전이 나왔어요'), findsOneWidget);
    expect(reloads, 0, reason: '보고 있는 화면은 갑자기 바뀌지 않음');

    // 닫아도 다른 앱에 갔다 오면 새 버전으로 바뀜
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.text('새 버전이 나왔어요'), findsNothing);
    await leaveAndComeBack(tester);
    await tester.pump();
    expect(reloads, 1);
  });

  testWidgets("'지금 업데이트'를 누르면 새로고침", (tester) async {
    var server = 'tap-1';
    var reloads = 0;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => AppUpdateWatcher(
        currentBuild: 'tap-1',
        fetchBuild: () async => server,
        reload: () => reloads++,
        checkEvery: const Duration(minutes: 1),
        child: child!,
      ),
      home: const Scaffold(body: Text('홈')),
    ));
    await tester.pump();
    server = 'tap-2';
    await tester.pump(const Duration(minutes: 1));
    await tester.pump();
    await tester.tap(find.text('지금 업데이트'));
    await tester.pump();
    expect(reloads, 1);
  });

  testWidgets('새로고침했는데도 예전 버전이 뜨면 또 새로고침하지 않고 안내만', (tester) async {
    var reloads = 0;
    // 첫 번째: 새로고침 시도
    await tester.pumpWidget(app(current: 'loop-1', server: () => 'loop-2', onReload: () => reloads++));
    await tester.pump();
    expect(reloads, 1);
    // 새로고침 뒤에도 같은 예전 앱이 다시 켜짐(캐시) → 반복하지 않음
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(current: 'loop-1', server: () => 'loop-2', onReload: () => reloads++));
    await tester.pump();
    expect(reloads, 1);
    expect(find.text('새 버전이 나왔어요'), findsOneWidget);
  });
}
