import 'dart:typed_data';
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

  static const xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  static const jsonMime = 'application/json';

  /// 파일 이름에 못 쓰는 글자를 빼고 정리
  static String safeName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
    return cleaned.isEmpty ? 'character' : cleaned;
  }
}
