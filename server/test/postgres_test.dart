import 'dart:io';
import 'dart:typed_data';
import 'package:mallangtalk_server/database/postgres_repository.dart';
import 'package:mallangtalk_server/store.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:mallangtalk_server/mallangtalk_server.dart'
    show buildHandler, ServerConfig;
import 'package:test/test.dart';
import '../bin/import_sqlite.dart';

// Use only a disposable, empty database: import intentionally refuses populated DBs.
void main() {
  final url = Platform.environment['TEST_DATABASE_URL'];
  test(
      'PostgreSQL imports exact SQLite rows and preserves authentication and state',
      () async {
    final pg = await PostgresRepository.open(url!);
    addTearDown(pg.close);
    final temp = await Directory.systemTemp.createTemp('mallangtalk-import-');
    addTearDown(() => temp.delete(recursive: true));
    final path = '${temp.path}/source.db';
    final sqlite = Store.open(path);
    final user = sqlite.createUser('migration_user', 'password123', '테스트')!;
    final token = sqlite.createSession(user.id);
    sqlite.saveCharacter('char1', user.id, '{"character":{"id":"char1"}}',
        published: true);
    final bytes = Uint8List.fromList([0, 1, 127, 255]);
    final image = sqlite.saveImage(user.id, 'image/png', bytes);
    sqlite.saveState(
        user.id, [(key: 'run_char1', value: '"원본 값"', updatedAt: 100)]);
    sqlite.close();
    final source = sqlite3.open(path, mode: OpenMode.readOnly);
    addTearDown(source.dispose);
    expect(
        (await pg.connection
            .withConnection((c) => importDatabase(source, c)))['users'],
        1);
    expect(
        (await pg.checkPassword('MIGRATION_USER', 'password123'))?.id, user.id);
    expect((await pg.userForToken(token))?.id, user.id);
    final api = buildHandler(const ServerConfig(keys: {}), store: pg);
    expect(
        (await api(shelf.Request('GET', Uri.parse('http://api/api/ready'))))
            .statusCode,
        200);
    expect(
        (await api(shelf.Request('GET', Uri.parse('http://api/api/me'),
                headers: {'authorization': 'Bearer $token'})))
            .statusCode,
        200);
    expect((await pg.image(image))?.bytes, bytes);
    await pg.saveState(
        user.id, [(key: 'run_char1', value: '"old"', updatedAt: 99)]);
    expect((await pg.stateOf(user.id))['run_char1']?.value, '"원본 값"');
    await Future.wait(List.generate(
        8,
        (i) => pg.saveState(
            user.id, [(key: 'parallel_$i', value: '$i', updatedAt: 101)])));
    expect((await pg.stateOf(user.id)).length, 9);
    expect(await pg.saveCharacter('char1', user.id, '{}', published: false),
        isTrue);
    final second = await pg.createUser('second_user', 'password123', '두번째');
    expect(second!.id, greaterThan(user.id));
    expect(await pg.saveCharacter('char1', second.id, '{}', published: true),
        isFalse);
    expect(await pg.deleteCharacter('char1', second.id), isFalse);
    await expectLater(
        pg.connection.withConnection((c) => importDatabase(source, c)),
        throwsStateError);
  },
      skip: url == null
          ? 'TEST_DATABASE_URL not set; requires a disposable PostgreSQL database'
          : false);
}
