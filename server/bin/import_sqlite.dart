import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:postgres/postgres.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:mallangtalk_server/database/migrations.dart';
import 'package:mallangtalk_server/database/sqlite_runtime.dart';

const transferTables = [
  'users',
  'sessions',
  'characters',
  'images',
  'user_state',
  'character_friends'
];

/// Import an extracted, consistent backup into an EMPTY PostgreSQL database.
/// Never opens Store: legacy startup cleanup must not alter migration input.
Future<void> main(List<String> args) async {
  final verifyOnly = args.length == 2 && args.first == '--verify-only';
  if ((!verifyOnly && args.length != 1) ||
      Platform.environment['DATABASE_URL'] == null) {
    stderr.writeln(
        'Usage: DATABASE_URL=... dart run bin/import_sqlite.dart [--verify-only] BACKUP/mallangtalk.db');
    exitCode = 64;
    return;
  }
  configureSqliteRuntime();
  final source = sqlite3.open(args.last, mode: OpenMode.readOnly);
  Connection? target;
  try {
    final integrity = source.select('PRAGMA integrity_check');
    if (integrity.length != 1 ||
        integrity.first.values.single != 'ok' ||
        source.select('PRAGMA foreign_key_check').isNotEmpty) {
      throw StateError('Source database failed integrity validation.');
    }
    target =
        await Connection.openFromUrl(Platform.environment['DATABASE_URL']!);
    final report = verifyOnly
        ? await verifyDatabase(source, target)
        : await importDatabase(source, target);
    stdout.writeln(jsonEncode({
      'imported': report,
      'verification': 'all rows and binary contents match'
    }));
  } finally {
    source.dispose();
    await target?.close();
  }
}

Future<Map<String, int>> verifyDatabase(Database source, Connection target) =>
    target.runTx((tx) async {
      final report = <String, int>{};
      for (final table in transferTables) {
        final rows = source
            .select('SELECT * FROM $table')
            .map((r) => Map<String, Object?>.from(r))
            .toList();
        if (table == 'users') {
          for (final row in rows) {
            row.putIfAbsent('avatar_url', () => '');
            row.putIfAbsent('intro', () => '');
          }
        }
        final copied = (await tx.execute('SELECT * FROM $table'))
            .map((r) => r.toColumnMap())
            .toList();
        if (rows.length != copied.length ||
            _fingerprint(rows) != _fingerprint(copied)) {
          throw StateError('Verification mismatch in $table.');
        }
        report[table] = rows.length;
      }
      return report;
    });

String _fingerprint(List<Map<String, Object?>> rows) {
  final canonical = rows
      .map((row) => {
            for (final key in row.keys.toList()..sort())
              key: row[key] is Uint8List
                  ? base64Encode(row[key] as Uint8List)
                  : row[key],
          })
      .map(jsonEncode)
      .toList()
    ..sort();
  return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
}

Future<Map<String, int>> importDatabase(
    Database source, Connection target) async {
  await migrate(target);
  return target.runTx((tx) async {
    // Block writes during import and refuse to merge with existing accounts.
    await tx.execute(
        'LOCK TABLE ${transferTables.join(',')} IN ACCESS EXCLUSIVE MODE');
    for (final table in transferTables) {
      if ((await tx.execute('SELECT count(*) FROM $table')).single.single !=
          0) {
        throw StateError('Target is not empty ($table). Nothing imported.');
      }
    }
    final report = <String, int>{};
    // Hold a source snapshot across every table, even if a caller uses a live DB.
    source.execute('BEGIN');
    try {
      for (final table in transferTables) {
        final rows = source
            .select('SELECT * FROM $table')
            .map((r) => Map<String, Object?>.from(r))
            .toList();
        for (final row in rows) {
          if (table == 'users') {
            row.putIfAbsent('avatar_url', () => '');
            row.putIfAbsent('intro', () => '');
          }
          final columns = row.keys.toList();
          final names = columns.map((c) => '"$c"').join(',');
          final placeholders =
              List.generate(columns.length, (i) => '\$${i + 1}').join(',');
          await tx.execute('INSERT INTO $table ($names) VALUES ($placeholders)',
              parameters: [for (final c in columns) row[c]]);
        }
        final copied = (await tx.execute('SELECT * FROM $table'))
            .map((r) => r.toColumnMap())
            .toList();
        if (rows.length != copied.length ||
            _fingerprint(rows) != _fingerprint(copied)) {
          throw StateError(
              'Verification mismatch in $table. Import rolled back.');
        }
        report[table] = rows.length;
      }
      await tx.execute(
          "SELECT setval(pg_get_serial_sequence('users','id'), COALESCE((SELECT max(id) FROM users),1), EXISTS(SELECT 1 FROM users))");
      return report;
    } finally {
      source.execute('ROLLBACK');
    }
  });
}
