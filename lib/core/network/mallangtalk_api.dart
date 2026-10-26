import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../shared/models/mallangtalk_models.dart';

/// 서버가 돌려준 오류 (화면에 그대로 보여 줄 수 있는 문장)
class ApiException implements Exception {
  final String message;
  /// 로그인이 풀렸는지 (다시 로그인 화면으로)
  final bool needLogin;
  const ApiException(this.message, {this.needLogin = false});
  @override
  String toString() => message;
}

/// 서버 계정
class AccountUser {
  final String username;
  final String nickname;
  const AccountUser({required this.username, required this.nickname});

  factory AccountUser.fromJson(Map json) =>
      AccountUser(username: json['username'] as String? ?? '', nickname: json['nickname'] as String? ?? '');

  Map<String, dynamic> toJson() => {'username': username, 'nickname': nickname};
}

/// 서버에 저장된 캐릭터 (받아오기 목록·내 캐릭터)
class ServerCharacter {
  final ScenarioBundle bundle;
  final String creator;
  final bool mine;
  /// 처음 올린 때 (말랑이 찾기 '최신' 정렬)
  final DateTime? createdAt;
  /// 친구로 추가한 사람 수 ('인기' 정렬)
  final int friends;
  const ServerCharacter({required this.bundle, required this.creator, required this.mine, this.createdAt, this.friends = 0});

  factory ServerCharacter.fromJson(Map json) => ServerCharacter(
        bundle: ScenarioBundle.fromJson(json['bundle'] as Map<String, dynamic>),
        creator: json['creator'] as String? ?? '',
        mine: json['mine'] == true,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
        friends: json['friends'] as int? ?? 0,
      );
}

/// 기기 연동 저장값 하나 (값은 String 또는 List<String>, 지웠으면 null)
class SyncedValue {
  final Object? value;
  final int updatedAt;
  const SyncedValue(this.value, this.updatedAt);
}

/// [초보자 노트] 말랑톡 서버의 계정·캐릭터 API를 부르는 클라이언트입니다. (서버 쪽은 server/lib/accounts.dart)
class MallangtalkApi {
  MallangtalkApi({required this.baseUrl, this.token, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              // 웹에서는 connectTimeout이 '응답이 올 때까지'라 큰 캐릭터·연동 값을 올리다 끊길 수 있어서 안 둠
              connectTimeout: kIsWeb ? null : const Duration(seconds: 10),
              receiveTimeout: const Duration(minutes: 2),
            ));

  final String baseUrl;
  final String? token;
  final Dio _dio;

  Options get _auth => Options(headers: {if (token != null) 'authorization': 'Bearer $token'});

  Future<Map<String, dynamic>> _send(String method, String path, {Object? data}) async {
    try {
      final response = await _dio.request<Map<String, dynamic>>(
        '$baseUrl$path',
        data: data,
        options: _auth.copyWith(method: method),
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      final body = e.response?.data;
      if (body is Map && body['error'] is String) {
        throw ApiException(body['error'] as String, needLogin: body['needLogin'] == true);
      }
      if (e.response == null) throw const ApiException('서버에 연결하지 못했어요. 잠시 후 다시 시도해 주세요.');
      throw ApiException('서버 오류 (${e.response?.statusCode})');
    }
  }

  Future<(String token, AccountUser user)> signup(String username, String password, String nickname) async {
    final json = await _send('POST', '/api/auth/signup',
        data: {'username': username, 'password': password, 'nickname': nickname});
    return (json['token'] as String, AccountUser.fromJson(json['user'] as Map));
  }

  Future<(String token, AccountUser user)> login(String username, String password) async {
    final json = await _send('POST', '/api/auth/login', data: {'username': username, 'password': password});
    return (json['token'] as String, AccountUser.fromJson(json['user'] as Map));
  }

  Future<void> logout() => _send('POST', '/api/auth/logout');

  Future<AccountUser> me() async => AccountUser.fromJson((await _send('GET', '/api/me'))['user'] as Map);

  Future<List<ServerCharacter>> publishedCharacters() async => _characters(await _send('GET', '/api/characters'));

  Future<List<ServerCharacter>> myCharacters() async => _characters(await _send('GET', '/api/my/characters'));

  /// 저장하면 서버가 사진을 DB로 옮긴 캐릭터 파일을 돌려줌 (사진은 /api/images/… 주소로)
  Future<ScenarioBundle> saveCharacter(ScenarioBundle bundle, {bool published = true}) async {
    final json = await _send('PUT', '/api/characters/${Uri.encodeComponent(bundle.character.id)}',
        data: {'bundle': bundle.toJson(), 'published': published});
    return ScenarioBundle.fromJson(json['bundle'] as Map<String, dynamic>);
  }

  Future<void> deleteCharacter(String id) => _send('DELETE', '/api/characters/${Uri.encodeComponent(id)}');

  /// 친구 추가·빼기 (말랑이 찾기 인기순에 쓰는 친구 수)
  Future<void> addFriend(String id) => _send('POST', '/api/characters/${Uri.encodeComponent(id)}/friend');

  Future<void> removeFriend(String id) => _send('DELETE', '/api/characters/${Uri.encodeComponent(id)}/friend');

  /// 기기 연동: 서버에 저장된 내 앱 저장값 전부 {키: (값, 바뀐 시각 ms)}. 값은 글자·글자 목록, 지운 값은 null
  Future<Map<String, SyncedValue>> myState() async {
    final json = await _send('GET', '/api/my/state');
    return {
      for (final MapEntry(:key, :value) in (json['items'] as Map? ?? const {}).entries)
        if (value is Map && value['updated_at'] is int)
          '$key': SyncedValue(_plain(value['value']), value['updated_at'] as int),
    };
  }

  Future<void> saveMyState(Map<String, SyncedValue> items) => _send('PUT', '/api/my/state', data: {
        'items': [
          for (final MapEntry(:key, :value) in items.entries)
            {'key': key, 'value': value.value, 'updated_at': value.updatedAt},
        ],
      });

  static Object? _plain(Object? value) => value is List ? [for (final v in value) '$v'] : value is String ? value : null;

  List<ServerCharacter> _characters(Map<String, dynamic> json) {
    final list = <ServerCharacter>[];
    for (final raw in json['characters'] as List? ?? const []) {
      try {
        list.add(ServerCharacter.fromJson(raw as Map));
      } catch (_) {
        // 깨진 캐릭터는 건너뜀
      }
    }
    return list;
  }
}
