import 'dart:convert';
import 'dart:typed_data';
import '../repository.dart';

const maxImageBytes = 4 * 1024 * 1024;

/// data: 사진 한 장을 DB에 넣고 /api/images/… 주소로. 이미 주소면 그대로
Future<String> storeImage(String value, int ownerId, Repository store) async {
  if (!value.startsWith('data:')) return value;
  final comma = value.indexOf(',');
  final header =
      comma < 0 ? '' : value.substring(5, comma); // image/jpeg;base64
  final mime = header.split(';').first;
  if (!header.endsWith(';base64') || !mime.startsWith('image/')) {
    throw const FormatException('사진 형식이 이상해요.');
  }
  final Uint8List bytes;
  try {
    bytes = base64Decode(value.substring(comma + 1));
  } on FormatException {
    throw const FormatException('사진을 읽지 못했어요.');
  }
  if (bytes.length > maxImageBytes)
    throw const FormatException('사진 한 장이 너무 커요 (4MB까지).');
  return '/api/images/${await store.saveImage(ownerId, mime, bytes)}';
}

/// 캐릭터 파일 안의 data: 사진(사진 표·프로필 사진)을 DB 사진으로 옮기고 주소만 남김
Future<Map<String, dynamic>> moveImagesToStore(
    Map<String, dynamic> bundle, int ownerId, Repository store) async {
  Future<String> moved(String value) => storeImage(value, ownerId, store);

  final images = bundle['images'];
  final character =
      Map<String, dynamic>.of(bundle['character'] as Map<String, dynamic>);
  if (character['avatar_url'] is String)
    character['avatar_url'] = await moved(character['avatar_url'] as String);
  return {
    ...bundle,
    'character': character,
    if (images is Map)
      'images': {
        for (final entry in images.entries)
          if (entry.value is String)
            '${entry.key}': await moved(entry.value as String),
      },
  };
}
