import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';

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

/// [초보자 노트] 프로필 사진을 골라 384px 크기로 줄인 뒤 data: 주소로 돌려줍니다.
/// (캐릭터 파일 안에 그대로 저장되니까 너무 크면 브라우저 저장 공간을 금방 채워서 줄여 둠)
Future<String?> pickProfileImage() async {
  final file = await FileIO.pick(extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif']);
  if (file == null) return null;
  final codec = await ui.instantiateImageCodec(file.bytes);
  final first = await codec.getNextFrame();
  final source = first.image;
  final scale = 384 / (source.width > source.height ? source.width : source.height);
  final width = scale < 1 ? (source.width * scale).round() : source.width;
  final height = scale < 1 ? (source.height * scale).round() : source.height;
  final resizedCodec = await ui.instantiateImageCodec(
    file.bytes,
    targetWidth: width,
    targetHeight: height,
  );
  final resized = (await resizedCodec.getNextFrame()).image;
  final png = await resized.toByteData(format: ui.ImageByteFormat.png);
  if (png == null) return null;
  return 'data:image/png;base64,${base64Encode(png.buffer.asUint8List())}';
}
