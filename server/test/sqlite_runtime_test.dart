import 'package:mallangtalk_server/database/sqlite_runtime.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  test('shared runtime loader opens SQLite before the importer uses it', () {
    configureSqliteRuntime();
    final db = sqlite3.openInMemory();
    try {
      db.execute('CREATE TABLE check_runtime (id INTEGER PRIMARY KEY)');
      db.execute('INSERT INTO check_runtime(id) VALUES (1)');
      expect(db.select('SELECT id FROM check_runtime').single['id'], 1);
    } finally {
      db.dispose();
    }
  });
}
