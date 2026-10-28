import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'domain/records.dart';
import 'repository.dart';
import 'http/json_body.dart';
import 'services/images.dart';

/// 캐릭터 파일 하나의 최대 크기 (사진은 따로 빼서 저장하니 대사만이면 넉넉함)
const maxCharacterBytes = 24 * 1024 * 1024;

/// 기기 연동 저장값: 한 번에 보내는 최대 크기와 이름 규칙 (#free 자유대화 방 키 포함)
const maxStateBytes = 32 * 1024 * 1024;
final _stateKey = RegExp(r'^[A-Za-z0-9_.:#-]{1,120}$');

final _username = RegExp(r'^[A-Za-z0-9_]{3,20}$');

/// [초보자 노트] 계정과 캐릭터 API. 해당하는 주소가 아니면 null을 돌려줘요.
/// - POST /api/auth/signup, /api/auth/login, /api/auth/logout, GET /api/me
/// - GET /api/characters (받아오기 목록), GET /api/characters/:id, GET /api/my/characters
/// - PUT·DELETE /api/characters/:id (내 캐릭터 저장·지우기), GET /api/images/:id (사진)
/// - POST·DELETE /api/characters/:id/friend (친구 추가·빼기. 말랑이 찾기 인기순에 쓰는 친구 수)
/// - PUT /api/my/profile (제작자 프로필: 별명·사진·한줄 소개)
/// - GET·PUT /api/my/state (내 프로필·진행도·앨범 같은 앱 저장값. PC와 폰 연동)
Future<Response?> accountsApi(Request request, Repository store) async {
  final segments = request.url.pathSegments; // ['api', ...]
  final method = request.method;
  final path = segments.skip(1).toList();

  switch (path) {
    case ['auth', 'signup'] when method == 'POST':
      final body = await readJsonBody(request, 64 * 1024);
      if (body == null) return _json(400, {'error': '요청 모양이 이상해요.'});
      final username = '${body['username'] ?? ''}'.trim();
      final password = '${body['password'] ?? ''}';
      final nickname = '${body['nickname'] ?? ''}'.trim();
      if (!_username.hasMatch(username)) {
        return _json(400, {'error': '아이디는 영문·숫자·밑줄(_)로 3~20자로 정해 주세요.'});
      }
      if (password.length < 8 || password.length > 100) {
        return _json(400, {'error': '비밀번호는 8자 이상으로 정해 주세요.'});
      }
      final user = await store.createUser(username, password,
          nickname.isEmpty ? username : _clip(nickname, 12));
      if (user == null)
        return _json(409, {'error': '이미 있는 아이디예요. 다른 아이디를 써 주세요.'});
      return _json(200,
          {'token': await store.createSession(user.id), 'user': user.toJson()});

    case ['auth', 'login'] when method == 'POST':
      final body = await readJsonBody(request, 64 * 1024);
      if (body == null) return _json(400, {'error': '요청 모양이 이상해요.'});
      final user = await store.checkPassword(
          '${body['username'] ?? ''}'.trim(), '${body['password'] ?? ''}');
      if (user == null) return _json(401, {'error': '아이디나 비밀번호가 맞지 않아요.'});
      return _json(200,
          {'token': await store.createSession(user.id), 'user': user.toJson()});

    case ['auth', 'logout'] when method == 'POST':
      final token = _token(request);
      if (token != null) await store.deleteSession(token);
      return _json(200, {'ok': true});

    case ['my', 'profile'] when method == 'PUT':
      final me = await _user(request, store);
      if (me == null) return _needLogin();
      final body = await readJsonBody(request, maxImageBytes + 64 * 1024);
      if (body == null) return _json(400, {'error': '요청 모양이 이상해요.'});
      String? nickname;
      if (body['nickname'] is String) {
        nickname = _clip('${body['nickname']}'.trim(), 12);
        if (nickname.isEmpty) return _json(400, {'error': '별명을 적어 주세요.'});
      }
      String? avatar;
      if (body['avatar_url'] is String) {
        try {
          avatar = await storeImage('${body['avatar_url']}', me.id, store);
        } on FormatException catch (e) {
          return _json(400, {'error': e.message});
        }
      }
      final intro = body['intro'] is String
          ? _clip('${body['intro']}'.trim(), 200)
          : null;
      final updated = await store.updateProfile(me.id,
          nickname: nickname, avatarUrl: avatar, intro: intro);
      if (updated == null) return _json(404, {'error': '계정을 찾지 못했어요.'});
      return _json(200, {'user': updated.toJson()});

    case ['me'] when method == 'GET':
      final user = await _user(request, store);
      if (user == null) return _needLogin();
      return _json(200, {'user': user.toJson()});

    case ['characters'] when method == 'GET':
      final me = await _user(request, store);
      return _json(200, {
        'characters': [
          for (final c in (await store.publishedCharacters()))
            _characterJson(c, me)
        ],
      });

    case ['my', 'characters'] when method == 'GET':
      final me = await _user(request, store);
      if (me == null) return _needLogin();
      return _json(200, {
        'characters': [
          for (final c in (await store.charactersOf(me.id)))
            _characterJson(c, me)
        ],
      });

    case ['my', 'state'] when method == 'GET':
      final me = await _user(request, store);
      if (me == null) return _needLogin();
      return _json(200, {
        'items': {
          for (final MapEntry(:key, :value)
              in (await store.stateOf(me.id)).entries)
            key: {
              'value': value.value == null ? null : jsonDecode(value.value!),
              'updated_at': value.updatedAt
            },
        },
      });

    case ['my', 'state'] when method == 'PUT':
      final me = await _user(request, store);
      if (me == null) return _needLogin();
      final body = await readJsonBody(request, maxStateBytes);
      final raw = body?['items'];
      if (raw is! List) return _json(400, {'error': '저장값이 너무 크거나 모양이 이상해요.'});
      final items = <({String key, String? value, int updatedAt})>[];
      for (final item in raw) {
        if (item is! Map ||
            item['key'] is! String ||
            item['updated_at'] is! int ||
            !_stateKey.hasMatch(item['key'] as String)) {
          return _json(400, {'error': '저장값 모양이 이상해요.'});
        }
        final value = item['value'];
        items.add((
          key: item['key'] as String,
          value: value == null ? null : jsonEncode(value),
          updatedAt: item['updated_at'] as int,
        ));
      }
      await store.saveState(me.id, items);
      return _json(200, {'ok': true});

    case ['characters', final id] when method == 'GET':
      final c = await store.character(id);
      final me = await _user(request, store);
      if (c == null || (!c.published && c.ownerId != me?.id))
        return _json(404, {'error': '없는 캐릭터예요.'});
      return _json(200, _characterJson(c, me));

    case ['characters', final id] when method == 'PUT':
      final me = await _user(request, store);
      if (me == null) return _needLogin();
      final body = await readJsonBody(request, maxCharacterBytes);
      final bundle = body?['bundle'];
      if (bundle is! Map<String, dynamic> ||
          bundle['character'] is! Map ||
          (bundle['character'] as Map)['id'] != id) {
        return _json(400, {'error': '캐릭터 파일이 너무 크거나 모양이 이상해요.'});
      }
      final existing = await store.character(id);
      if (existing != null && existing.ownerId != me.id) {
        return _json(403, {'error': '다른 사람이 만든 캐릭터는 고칠 수 없어요.'});
      }
      final String saved;
      try {
        saved = jsonEncode(await moveImagesToStore(bundle, me.id, store));
      } on FormatException catch (e) {
        return _json(400, {'error': e.message});
      }
      await store.saveCharacter(id, me.id, saved,
          published: body!['published'] != false);
      return _json(200, _characterJson((await store.character(id))!, me));

    case ['characters', final id, 'friend'] when method == 'POST':
      final me = await _user(request, store);
      if (me == null) return _needLogin();
      if (!(await store.addFriend(me.id, id)))
        return _json(404, {'error': '없는 캐릭터예요.'});
      return _json(200, {'ok': true});

    case ['characters', final id, 'friend'] when method == 'DELETE':
      final me = await _user(request, store);
      if (me == null) return _needLogin();
      await store.removeFriend(me.id, id);
      return _json(200, {'ok': true});

    case ['characters', final id] when method == 'DELETE':
      final me = await _user(request, store);
      if (me == null) return _needLogin();
      if (!(await store.deleteCharacter(id, me.id)))
        return _json(404, {'error': '지울 수 있는 내 캐릭터가 아니에요.'});
      return _json(200, {'ok': true});

    case ['images', final id] when method == 'GET':
      final image = await store.image(id);
      if (image == null) return Response.notFound('');
      return Response.ok(image.bytes, headers: {
        'content-type': image.mime,
        // 사진 번호가 내용으로 정해져서 바뀔 일이 없으니 오래 캐시
        'cache-control': 'public, max-age=31536000, immutable',
      });
  }
  return null;
}

Map<String, dynamic> _characterJson(CharacterRecord c, UserRecord? me) => {
      'id': c.id,
      'creator': c.ownerNickname,
      'creator_avatar': c.ownerAvatar,
      'creator_intro': c.ownerIntro,
      'mine': me?.id == c.ownerId,
      'published': c.published,
      'created_at': c.createdAt.toIso8601String(),
      'updated_at': c.updatedAt.toIso8601String(),
      'friends': c.friendCount,
      'bundle': jsonDecode(c.bundleJson),
    };

String? _token(Request request) {
  final header = request.headers['authorization'];
  if (header == null || !header.startsWith('Bearer ')) return null;
  return header.substring(7).trim();
}

Future<UserRecord?> _user(Request request, Repository store) async {
  final token = _token(request);
  return token == null || token.isEmpty
      ? null
      : await store.userForToken(token);
}

Response _needLogin() =>
    _json(401, {'error': '로그인이 필요해요. 다시 로그인해 주세요.', 'needLogin': true});

String _clip(String text, int max) =>
    text.length <= max ? text : text.substring(0, max);

Response _json(int status, Map<String, dynamic> body) => Response(
      status,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
