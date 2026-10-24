import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:file_picker/file_picker.dart';
import '../widgets/photo_crop_screen.dart';

/// 고른 파일 (이름 + 내용)
class PickedFile {
  final String name;
  final Uint8List bytes;
  const PickedFile(this.name, this.bytes);

  String get extension => name.contains('.') ? name.split('.').last.toLowerCase() : '';
}

/// [초보자 노트] 파일 열기/저장을 한곳에 모았습니다. 웹에서는 저장하면 '다운로드' 폴더로 내려받아집니다.
class FileIO {
  FileIO._();

  static Future<PickedFile?> pick({required List<String> extensions}) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    if (file == null) return null;
    return PickedFile(file.name, await file.readAsBytes());
  }

  static Future<void> save({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    await FilePicker.saveFile(fileName: fileName, bytes: bytes, mimeType: mimeType);
  }

  static const jsonMime = 'application/json';

  /// 파일 이름에 못 쓰는 글자를 빼고 정리
  static String safeName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
    return cleaned.isEmpty ? 'character' : cleaned;
  }
}

/// [초보자 노트] 프로필 사진을 골라 자르기 화면(동그라미 1:1)에서 위치·크기를 맞춘 뒤
/// 384px로 줄여 data: 주소로 돌려줍니다. 고르다 취소하면 null.
/// (캐릭터 파일 안에 그대로 저장되니까 너무 크면 브라우저 저장 공간을 금방 채워서 줄여 둠)
Future<String?> pickProfileImage(BuildContext context) async {
  final file = await FileIO.pick(extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif']);
  if (file == null || !context.mounted) return null;
  return showPhotoCropScreen(context, bytes: file.bytes, shape: PhotoCropShape.profile, maxSide: 384);
}

/// [초보자 노트] 사진 말풍선·컷씬에 넣을 사진을 골라 자르기 화면에서 영역을 정한 뒤 긴 쪽 960px로 줄여
/// data: 주소로 돌려줍니다. 웹에서는 JPEG로 줄여서 한 장에 100~200KB 정도예요. 캐릭터 파일 안에 저장되니
/// 너무 많이 넣으면 브라우저 저장 공간(약 5MB)이 찰 수 있어요. (DB 저장 단계에서 서버로 옮길 예정)
Future<String?> pickPhoto(BuildContext context) async {
  final file = await FileIO.pick(extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif']);
  if (file == null || !context.mounted) return null;
  return showPhotoCropScreen(context, bytes: file.bytes, shape: PhotoCropShape.photo, maxSide: 960);
}
