import 'dart:ffi';
import 'package:sqlite3/open.dart';

/// Debian runtime packages provide the versioned .so.0; the unversioned .so
/// normally belongs to the development package. Configure before first use.
void configureSqliteRuntime() {
  open.overrideFor(OperatingSystem.linux, () {
    Object? lastError;
    for (final name in [
      'libsqlite3.so.0',
      'libsqlite3.so',
      '/usr/lib/x86_64-linux-gnu/libsqlite3.so.0',
      '/usr/lib/aarch64-linux-gnu/libsqlite3.so.0',
      '/usr/lib/libsqlite3.so.0',
    ]) {
      try {
        return DynamicLibrary.open(name);
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError(
        'SQLite runtime library not found. Install libsqlite3-0. ($lastError)');
  });
}
