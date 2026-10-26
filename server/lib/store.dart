import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

/// 로그인한 유저
class UserRecord {
  final int id;
  final String username;
  final String nickname;
  /// 제작자 프로필 사진 (/api/images/… 주소, 안 올렸으면 빈 글자)
  final String avatarUrl;
  /// 제작자 한줄 소개
  final String intro;
  const UserRecord(this.id, this.username, this.nickname, {this.avatarUrl = '', this.intro = ''});

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'nickname': nickname,
        'avatar_url': avatarUrl,
        'intro': intro,
      };
}

/// 서버에 저장된 캐릭터 하나 (bundle은 앱의 캐릭터 파일 JSON 그대로)
class CharacterRecord {
  final String id;
  final int ownerId;
  final String ownerNickname;
  /// 제작자 프로필 사진·한줄 소개 (말랑이 찾기 카드와 제작자 프로필에 보임)
  final String ownerAvatar;
  final String ownerIntro;
  final bool published;
  final DateTime createdAt;

  /// 이 캐릭터를 친구로 추가한 사람 수 (말랑이 찾기 '인기' 정렬)
  final int friendCount;
  final String bundleJson;
  final DateTime updatedAt;
  const CharacterRecord(this.id, this.ownerId, this.ownerNickname, this.published, this.bundleJson, this.updatedAt,
      {DateTime? createdAt, this.friendCount = 0, this.ownerAvatar = '', this.ownerIntro = ''})
      : createdAt = createdAt ?? updatedAt;
}

/// [초보자 노트] 말랑톡 서버의 DB (SQLite 파일 하나: DATA_DIR/mallangtalk.db).
/// - users: 아이디, 비밀번호(그대로 저장하지 않고 PBKDF2로 바꾼 값), 닉네임
/// - sessions: 로그인 표 (토큰). 90일 지나면 다시 로그인
/// - characters: 유저가 만든 캐릭터 파일. published면 '받아오기'에 보임
/// - images: 캐릭터에 올린 사진 (프로필·사진 말풍선·컷씬). 캐릭터 파일에는 사진 주소만 남김
/// - user_state: 유저의 앱 저장값 (내 프로필·친구 목록·진행도·앨범…). PC와 폰이 같은 값을 보게
class Store {
  Store._(this._db);

  final Database _db;

  static const sessionDays = 90;
  static const _iterations = 60000;

  factory Store.open(String path) {
    if (path != ':memory:') Directory(File(path).parent.path).createSync(recursive: true);
    final db = path == ':memory:' ? sqlite3.openInMemory() : sqlite3.open(path);
    db.execute('PRAGMA journal_mode = WAL;');
    db.execute('PRAGMA foreign_keys = ON;');
    db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL UNIQUE COLLATE NOCASE,
        password_hash TEXT NOT NULL,
        salt TEXT NOT NULL,
        nickname TEXT NOT NULL,
        created_at TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS sessions (
        token_hash TEXT PRIMARY KEY,
        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        expires_at TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS characters (
        id TEXT PRIMARY KEY,
        owner_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        published INTEGER NOT NULL DEFAULT 1,
        bundle TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS characters_owner ON characters(owner_id);
      CREATE TABLE IF NOT EXISTS images (
        id TEXT PRIMARY KEY,
        owner_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        mime TEXT NOT NULL,
        data BLOB NOT NULL,
        created_at TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS user_state (
        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        key TEXT NOT NULL,
        value TEXT,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (user_id, key)
      );
      CREATE TABLE IF NOT EXISTS character_friends (
        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        character_id TEXT NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
        created_at TEXT NOT NULL,
        PRIMARY KEY (user_id, character_id)
      );
      CREATE INDEX IF NOT EXISTS character_friends_character ON character_friends(character_id);
    ''');
    // 예전에 만든 DB에도 제작자 프로필 칸을 더해 둠
    final userColumns = {for (final row in db.select('PRAGMA table_info(users)')) row['name'] as String};
    if (!userColumns.contains('avatar_url')) {
      db.execute("ALTER TABLE users ADD COLUMN avatar_url TEXT NOT NULL DEFAULT ''");
    }
    if (!userColumns.contains('intro')) {
      db.execute("ALTER TABLE users ADD COLUMN intro TEXT NOT NULL DEFAULT ''");
    }
    return Store._(db);
  }

  void close() => _db.dispose();

  // ───────────── 유저 ─────────────

  /// 회원가입. 같은 아이디가 있으면 null
  UserRecord? createUser(String username, String password, String nickname) {
    if (_db.select('SELECT 1 FROM users WHERE username = ?', [username]).isNotEmpty) return null;
    final salt = _randomToken(16);
    _db.execute(
      'INSERT INTO users (username, password_hash, salt, nickname, created_at) VALUES (?, ?, ?, ?, ?)',
      [username, _hashPassword(password, salt), salt, nickname, _now()],
    );
    return UserRecord(_db.lastInsertRowId, username, nickname);
  }

  /// 아이디·비밀번호가 맞으면 유저
  UserRecord? checkPassword(String username, String password) {
    final rows = _db.select(
        'SELECT id, username, nickname, avatar_url, intro, password_hash, salt FROM users WHERE username = ?',
        [username]);
    if (rows.isEmpty) {
      _hashPassword(password, 'no-such-user'); // 없는 아이디도 같은 시간이 걸리게
      return null;
    }
    final row = rows.first;
    final expected = row['password_hash'] as String;
    if (!_constantTimeEquals(_hashPassword(password, row['salt'] as String), expected)) return null;
    return _userFrom(row);
  }

  // ───────────── 로그인 표 ─────────────

  /// 새 로그인 토큰. DB에는 토큰의 해시만 저장
  String createSession(int userId) {
    final token = _randomToken(32);
    final expires = DateTime.now().toUtc().add(const Duration(days: sessionDays)).toIso8601String();
    _db.execute('INSERT INTO sessions (token_hash, user_id, expires_at) VALUES (?, ?, ?)', [_sha(token), userId, expires]);
    return token;
  }

  UserRecord? userForToken(String token) {
    final rows = _db.select('''
      SELECT u.id, u.username, u.nickname, u.avatar_url, u.intro, s.expires_at
      FROM sessions s JOIN users u ON u.id = s.user_id
      WHERE s.token_hash = ?''', [_sha(token)]);
    if (rows.isEmpty) return null;
    final row = rows.first;
    if (DateTime.parse(row['expires_at'] as String).isBefore(DateTime.now().toUtc())) {
      deleteSession(token);
      return null;
    }
    return _userFrom(row);
  }

  void deleteSession(String token) => _db.execute('DELETE FROM sessions WHERE token_hash = ?', [_sha(token)]);

  // ───────────── 캐릭터 ─────────────

  CharacterRecord? character(String id) {
    final rows = _db.select('''
      SELECT c.*, u.nickname, u.avatar_url, u.intro, (SELECT COUNT(*) FROM character_friends f WHERE f.character_id = c.id) AS friends FROM characters c JOIN users u ON u.id = c.owner_id WHERE c.id = ?''', [id]);
    return rows.isEmpty ? null : _characterFrom(rows.first);
  }

  /// 공개된 캐릭터 (최근에 고친 순)
  List<CharacterRecord> publishedCharacters() => [
        for (final row in _db.select('''
          SELECT c.*, u.nickname, u.avatar_url, u.intro, (SELECT COUNT(*) FROM character_friends f WHERE f.character_id = c.id) AS friends FROM characters c JOIN users u ON u.id = c.owner_id
          WHERE c.published = 1 ORDER BY c.updated_at DESC'''))
          _characterFrom(row),
      ];

  List<CharacterRecord> charactersOf(int ownerId) => [
        for (final row in _db.select('''
          SELECT c.*, u.nickname, u.avatar_url, u.intro, (SELECT COUNT(*) FROM character_friends f WHERE f.character_id = c.id) AS friends FROM characters c JOIN users u ON u.id = c.owner_id
          WHERE c.owner_id = ? ORDER BY c.updated_at DESC''', [ownerId]))
          _characterFrom(row),
      ];

  /// 저장 (새로 넣거나 고치기). 다른 사람 캐릭터면 false
  bool saveCharacter(String id, int ownerId, String bundleJson, {required bool published}) {
    final existing = character(id);
    if (existing != null && existing.ownerId != ownerId) return false;
    final now = _now();
    if (existing == null) {
      _db.execute(
        'INSERT INTO characters (id, owner_id, published, bundle, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
        [id, ownerId, published ? 1 : 0, bundleJson, now, now],
      );
    } else {
      _db.execute('UPDATE characters SET published = ?, bundle = ?, updated_at = ? WHERE id = ?',
          [published ? 1 : 0, bundleJson, now, id]);
    }
    return true;
  }

  /// 지우기. 내 캐릭터가 아니면 false
  bool deleteCharacter(String id, int ownerId) {
    final existing = character(id);
    if (existing == null || existing.ownerId != ownerId) return false;
    _db.execute('DELETE FROM characters WHERE id = ?', [id]);
    return true;
  }

  /// 친구 추가 (공개된 캐릭터만, 내 캐릭터는 세지 않음). 이미 했으면 그대로
  bool addFriend(int userId, String characterId) {
    final c = character(characterId);
    if (c == null || !c.published) return false;
    if (c.ownerId == userId) return true;
    _db.execute('INSERT OR IGNORE INTO character_friends (user_id, character_id, created_at) VALUES (?, ?, ?)',
        [userId, characterId, _now()]);
    return true;
  }

  void removeFriend(int userId, String characterId) =>
      _db.execute('DELETE FROM character_friends WHERE user_id = ? AND character_id = ?', [userId, characterId]);

  CharacterRecord _characterFrom(Row row) => CharacterRecord(
        row['id'] as String,
        row['owner_id'] as int,
        row['nickname'] as String,
        (row['published'] as int) == 1,
        row['bundle'] as String,
        DateTime.parse(row['updated_at'] as String),
        createdAt: DateTime.parse(row['created_at'] as String),
        friendCount: row['friends'] as int? ?? 0,
        ownerAvatar: row['avatar_url'] as String? ?? '',
        ownerIntro: row['intro'] as String? ?? '',
      );

  UserRecord _userFrom(Row row) => UserRecord(
        row['id'] as int,
        row['username'] as String,
        row['nickname'] as String,
        avatarUrl: row['avatar_url'] as String? ?? '',
        intro: row['intro'] as String? ?? '',
      );

  /// 제작자 프로필 바꾸기 (준 값만). 사진은 이미 /api/images/… 주소로 바꿔 둔 것
  UserRecord? updateProfile(int userId, {String? nickname, String? avatarUrl, String? intro}) {
    if (nickname != null) _db.execute('UPDATE users SET nickname = ? WHERE id = ?', [nickname, userId]);
    if (avatarUrl != null) _db.execute('UPDATE users SET avatar_url = ? WHERE id = ?', [avatarUrl, userId]);
    if (intro != null) _db.execute('UPDATE users SET intro = ? WHERE id = ?', [intro, userId]);
    final rows = _db.select('SELECT id, username, nickname, avatar_url, intro FROM users WHERE id = ?', [userId]);
    return rows.isEmpty ? null : _userFrom(rows.first);
  }

  // ───────────── 사진 ─────────────

  /// 사진 저장. 번호는 사진 내용으로 정해서 같은 사진은 한 번만 저장됨
  String saveImage(int ownerId, String mime, Uint8List bytes) {
    final id = sha256.convert(bytes).toString().substring(0, 32);
    _db.execute(
      'INSERT OR IGNORE INTO images (id, owner_id, mime, data, created_at) VALUES (?, ?, ?, ?, ?)',
      [id, ownerId, mime, bytes, _now()],
    );
    return id;
  }

  ({String mime, Uint8List bytes})? image(String id) {
    final rows = _db.select('SELECT mime, data FROM images WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    return (mime: rows.first['mime'] as String, bytes: rows.first['data'] as Uint8List);
  }

  // ───────────── 앱 저장값 (기기 연동) ─────────────

  /// 이 유저의 저장값 전부. value는 JSON 글자 (지운 값은 null)
  Map<String, ({String? value, int updatedAt})> stateOf(int userId) => {
        for (final row in _db.select('SELECT key, value, updated_at FROM user_state WHERE user_id = ?', [userId]))
          row['key'] as String: (value: row['value'] as String?, updatedAt: row['updated_at'] as int),
      };

  /// 저장값 여러 개를 한 번에. 서버에 더 나중에 바뀐 값이 있으면 그건 건드리지 않음
  void saveState(int userId, List<({String key, String? value, int updatedAt})> items) {
    final statement = _db.prepare('''
      INSERT INTO user_state (user_id, key, value, updated_at) VALUES (?, ?, ?, ?)
      ON CONFLICT (user_id, key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
      WHERE excluded.updated_at >= user_state.updated_at''');
    _db.execute('BEGIN');
    try {
      for (final item in items) {
        statement.execute([userId, item.key, item.value, item.updatedAt]);
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    } finally {
      statement.dispose();
    }
  }

  // ───────────── 도우미 ─────────────

  static String _now() => DateTime.now().toUtc().toIso8601String();

  static String _randomToken(int bytes) {
    final random = Random.secure();
    return base64UrlEncode(List.generate(bytes, (_) => random.nextInt(256))).replaceAll('=', '');
  }

  static String _sha(String text) => sha256.convert(utf8.encode(text)).toString();

  /// PBKDF2-HMAC-SHA256 (비밀번호를 되돌릴 수 없는 값으로)
  static String _hashPassword(String password, String salt) {
    final hmac = Hmac(sha256, utf8.encode(password));
    final block = Uint8List.fromList([...utf8.encode(salt), 0, 0, 0, 1]);
    var u = hmac.convert(block).bytes;
    final result = List<int>.of(u);
    for (var i = 1; i < _iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < result.length; j++) {
        result[j] ^= u[j];
      }
    }
    return base64Encode(result);
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
