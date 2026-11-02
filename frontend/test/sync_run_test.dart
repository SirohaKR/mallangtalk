import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/core/network/mallangtalk_api.dart';
import 'package:mallangtalk/core/storage/local_store.dart';
import 'package:mallangtalk/features/auth/state_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api extends MallangtalkApi {
  _Api(this.state) : super(baseUrl: 'http://nas.local', token: 't');
  final Map<String, SyncedValue> state;
  @override
  Future<Map<String, SyncedValue>> myState() async => {...state};
  @override
  Future<void> saveMyState(Map<String, SyncedValue> items) async {
    for (final e in items.entries) {
      if ((state[e.key]?.updatedAt ?? -1) <= e.value.updatedAt) state[e.key] = e.value;
    }
  }
}

String run(String prefix, int count, DateTime start) => jsonEncode({
      'affection': 0,
      'flags': [],
      'completed_event_ids': [],
      'messages': [
        for (var i = 0; i < count; i++)
          {
            'id': '$prefix$i',
            'is_user': i.isOdd,
            'text': '톡 $i',
            'timestamp': start.add(Duration(minutes: i)).toIso8601String(),
          }
      ],
    });

void main() {
  test('자유대화를 비우고 새로 한 대화를, 다른 기기에 남은 비우기 전 더 긴 대화가 덮지 않음', () async {
    // 폰: 11/1에 비우고 새로 10개 (서버에 올라가 있음)
    final phone = run('new', 10, DateTime(2026, 11, 1, 20));
    final api = _Api({'run_c#free': SyncedValue(phone, 1000)});
    // PC: 10/30의 비우기 전 대화 40개, 더 최근 시각으로 쓰여 있음
    SharedPreferences.setMockInitialValues({
      'sync_user': 'jjaet',
      'sync_base_v1': 'jjaet',
      'run_c#free': run('old', 40, DateTime(2026, 10, 30, 20)),
      'sync_ts_v1': '{"run_c#free":2000}',
    });
    final store = LocalStore(await SharedPreferences.getInstance());
    await syncState(api, store, 'jjaet');
    expect(api.state['run_c#free']!.value, phone);
    expect(store.rawValue('run_c#free'), phone);
  });
}
