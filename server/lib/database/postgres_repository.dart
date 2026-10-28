import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:postgres/postgres.dart';
import '../repository.dart';
import '../domain/records.dart';
import '../security/credentials.dart';
import 'migrations.dart';

class PostgresRepository implements Repository {
  PostgresRepository(this.connection);
  final Pool<void> connection;

  static Future<PostgresRepository> open(String url) async {
    final connection = Pool<void>.withUrl(url);
    try {
      await connection.withConnection(migrate);
      return PostgresRepository(connection);
    } catch (_) {
      await connection.close();
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _rows(String sql,
          [List<Object?> args = const []]) async =>
      (await connection.execute(sql, parameters: args))
          .map((r) => r.toColumnMap())
          .toList();
  Future<void> _exec(String sql, [List<Object?> args = const []]) async {
    await connection.execute(sql, parameters: args);
  }

  @override
  Future<void> close() => connection.close();
  @override
  Future<void> ping() => _exec('SELECT 1');

  UserRecord _user(Map<String, dynamic> r) => UserRecord(
      r['id'] as int, r['username'] as String, r['nickname'] as String,
      avatarUrl: r['avatar_url'] as String? ?? '',
      intro: r['intro'] as String? ?? '');

  @override
  Future<UserRecord?> createUser(
      String username, String password, String nickname) async {
    final salt = Credentials.randomToken(16);
    final rows = await _rows(
        r'''INSERT INTO users(username,password_hash,salt,nickname,created_at)
      VALUES ($1,$2,$3,$4,$5) ON CONFLICT DO NOTHING RETURNING *''',
        [
          username,
          Credentials.hashPassword(password, salt),
          salt,
          nickname,
          Credentials.now()
        ]);
    return rows.isEmpty ? null : _user(rows.first);
  }

  @override
  Future<UserRecord?> checkPassword(String username, String password) async {
    final rows = await _rows(
        r'SELECT * FROM users WHERE lower(username)=lower($1)', [username]);
    if (rows.isEmpty) {
      Credentials.hashPassword(password, 'no-such-user');
      return null;
    }
    final row = rows.first;
    return Credentials.constantTimeEquals(
            Credentials.hashPassword(password, row['salt'] as String),
            row['password_hash'] as String)
        ? _user(row)
        : null;
  }

  @override
  Future<String> createSession(int userId) async {
    final token = Credentials.randomToken(32);
    await _exec(
        r'INSERT INTO sessions(token_hash,user_id,expires_at) VALUES ($1,$2,$3)',
        [
          Credentials.sha(token),
          userId,
          DateTime.now().toUtc().add(const Duration(days: 90)).toIso8601String()
        ]);
    return token;
  }

  @override
  Future<UserRecord?> userForToken(String token) async {
    final rows = await _rows(r'''SELECT u.*,s.expires_at FROM users u
      JOIN sessions s ON s.user_id=u.id WHERE s.token_hash=$1''',
        [Credentials.sha(token)]);
    if (rows.isEmpty) return null;
    if (DateTime.parse(rows.first['expires_at'] as String)
        .isBefore(DateTime.now().toUtc())) {
      await deleteSession(token);
      return null;
    }
    return _user(rows.first);
  }

  @override
  Future<void> deleteSession(String token) => _exec(
      r'DELETE FROM sessions WHERE token_hash=$1', [Credentials.sha(token)]);

  static const _characters = '''SELECT c.*,u.nickname,u.avatar_url,u.intro,
    (SELECT count(*) FROM character_friends f WHERE f.character_id=c.id) AS friends
    FROM characters c JOIN users u ON u.id=c.owner_id''';
  CharacterRecord _character(Map<String, dynamic> r) => CharacterRecord(
      r['id'] as String,
      r['owner_id'] as int,
      r['nickname'] as String,
      r['published'] == 1,
      r['bundle'] as String,
      DateTime.parse(r['updated_at'] as String),
      createdAt: DateTime.parse(r['created_at'] as String),
      friendCount: r['friends'] as int,
      ownerAvatar: r['avatar_url'] as String,
      ownerIntro: r['intro'] as String);
  @override
  Future<CharacterRecord?> character(String id) async {
    final rows = await _rows('$_characters WHERE c.id=\$1', [id]);
    return rows.isEmpty ? null : _character(rows.first);
  }

  @override
  Future<List<CharacterRecord>> publishedCharacters() async => (await _rows(
          '$_characters WHERE c.published=1 ORDER BY c.updated_at DESC'))
      .map(_character)
      .toList();
  @override
  Future<List<CharacterRecord>> charactersOf(int ownerId) async => (await _rows(
          '$_characters WHERE c.owner_id=\$1 ORDER BY c.updated_at DESC',
          [ownerId]))
      .map(_character)
      .toList();
  @override
  Future<bool> saveCharacter(String id, int ownerId, String bundleJson,
      {required bool published}) async {
    final now = Credentials.now();
    final rows = await _rows(
        r'''INSERT INTO characters(id,owner_id,published,bundle,created_at,updated_at)
      VALUES ($1,$2,$3,$4,$5,$5) ON CONFLICT(id) DO UPDATE
      SET published=excluded.published,bundle=excluded.bundle,updated_at=excluded.updated_at
      WHERE characters.owner_id=excluded.owner_id RETURNING id''',
        [id, ownerId, published ? 1 : 0, bundleJson, now]);
    return rows.isNotEmpty;
  }

  @override
  Future<bool> deleteCharacter(String id, int ownerId) async => (await _rows(
          r'DELETE FROM characters WHERE id=$1 AND owner_id=$2 RETURNING id',
          [id, ownerId]))
      .isNotEmpty;
  @override
  Future<bool> addFriend(int userId, String characterId) async {
    final c = await character(characterId);
    if (c == null || !c.published) return false;
    if (c.ownerId == userId) return true;
    await _exec(
        r'''INSERT INTO character_friends(user_id,character_id,created_at)
      SELECT $1,id,$3 FROM characters WHERE id=$2 AND published=1 ON CONFLICT DO NOTHING''',
        [userId, characterId, Credentials.now()]);
    return true;
  }

  @override
  Future<void> removeFriend(int userId, String characterId) => _exec(
      r'DELETE FROM character_friends WHERE user_id=$1 AND character_id=$2',
      [userId, characterId]);
  @override
  Future<UserRecord?> updateProfile(int userId,
      {String? nickname, String? avatarUrl, String? intro}) async {
    final rows = await _rows(
        r'''UPDATE users SET nickname=COALESCE($2,nickname),
      avatar_url=COALESCE($3,avatar_url),intro=COALESCE($4,intro) WHERE id=$1 RETURNING *''',
        [userId, nickname, avatarUrl, intro]);
    return rows.isEmpty ? null : _user(rows.first);
  }

  @override
  Future<String> saveImage(int ownerId, String mime, Uint8List bytes) async {
    final id = sha256.convert(bytes).toString().substring(0, 32);
    await _exec(r'''INSERT INTO images(id,owner_id,mime,data,created_at)
      VALUES ($1,$2,$3,$4,$5) ON CONFLICT DO NOTHING''',
        [id, ownerId, mime, bytes, Credentials.now()]);
    return id;
  }

  @override
  Future<StoredImage?> image(String id) async {
    final rows = await _rows(r'SELECT mime,data FROM images WHERE id=$1', [id]);
    return rows.isEmpty
        ? null
        : (
            mime: rows.first['mime'] as String,
            bytes: rows.first['data'] as Uint8List
          );
  }

  @override
  Future<Map<String, StateValue>> stateOf(int userId) async => {
        for (final r in await _rows(
            r'SELECT key,value,updated_at FROM user_state WHERE user_id=$1',
            [userId]))
          r['key'] as String: (
            value: r['value'] as String?,
            updatedAt: r['updated_at'] as int
          )
      };
  @override
  Future<void> saveState(int userId, List<StateItem> items) =>
      connection.runTx((tx) async {
        for (final item in items) {
          await tx.execute(
              r'''INSERT INTO user_state(user_id,key,value,updated_at) VALUES ($1,$2,$3,$4)
        ON CONFLICT(user_id,key) DO UPDATE SET value=excluded.value,updated_at=excluded.updated_at
        WHERE excluded.updated_at>=user_state.updated_at''',
              parameters: [userId, item.key, item.value, item.updatedAt]);
        }
      });
}
