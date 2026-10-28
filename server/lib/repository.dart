import 'dart:async';
import 'dart:typed_data';
import 'domain/records.dart';

typedef StateItem = ({String key, String? value, int updatedAt});
typedef StateValue = ({String? value, int updatedAt});
typedef StoredImage = ({String mime, Uint8List bytes});

/// HTTP handlers depend on this contract, never on a database driver.
/// SQLite remains synchronous for compatibility; network databases are async.
abstract interface class Repository {
  FutureOr<void> close();
  FutureOr<void> ping();
  FutureOr<UserRecord?> createUser(
      String username, String password, String nickname);
  FutureOr<UserRecord?> checkPassword(String username, String password);
  FutureOr<String> createSession(int userId);
  FutureOr<UserRecord?> userForToken(String token);
  FutureOr<void> deleteSession(String token);
  FutureOr<CharacterRecord?> character(String id);
  FutureOr<List<CharacterRecord>> publishedCharacters();
  FutureOr<List<CharacterRecord>> charactersOf(int ownerId);
  FutureOr<bool> saveCharacter(String id, int ownerId, String bundleJson,
      {required bool published});
  FutureOr<bool> deleteCharacter(String id, int ownerId);
  FutureOr<bool> addFriend(int userId, String characterId);
  FutureOr<void> removeFriend(int userId, String characterId);
  FutureOr<UserRecord?> updateProfile(int userId,
      {String? nickname, String? avatarUrl, String? intro});
  FutureOr<String> saveImage(int ownerId, String mime, Uint8List bytes);
  FutureOr<StoredImage?> image(String id);
  FutureOr<Map<String, StateValue>> stateOf(int userId);
  FutureOr<void> saveState(int userId, List<StateItem> items);
}
