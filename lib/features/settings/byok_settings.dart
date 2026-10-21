import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/claude_chat_client.dart';
import '../../core/storage/local_store.dart';

/// 내 AI 키(BYOK) 설정 상태
class ByokSettings {
  final String? apiKey;
  final String model;

  const ByokSettings({this.apiKey, required this.model});

  bool get hasKey => apiKey != null && apiKey!.isNotEmpty;

  /// 화면에 보여줄 때는 키 앞뒤 몇 글자만
  String get maskedKey {
    final key = apiKey ?? '';
    if (key.length <= 12) return '••••';
    return '${key.substring(0, 7)}••••${key.substring(key.length - 4)}';
  }
}

/// [초보자 노트] 설정 화면과 채팅방이 함께 보는 BYOK 설정 보관함입니다.
/// 키는 이 브라우저(localStorage)에만 저장되고, 서버로 따로 보내지 않습니다.
class ByokSettingsNotifier extends Notifier<ByokSettings> {
  @override
  ByokSettings build() {
    final store = ref.watch(localStoreProvider);
    return ByokSettings(
      apiKey: store.apiKey,
      model: store.model ?? ClaudeModelOption.defaultId,
    );
  }

  Future<void> save({required String apiKey, required String model}) async {
    await ref.read(localStoreProvider).saveByok(apiKey: apiKey.trim(), model: model);
    state = ByokSettings(apiKey: apiKey.trim(), model: model);
  }

  Future<void> removeKey() async {
    await ref.read(localStoreProvider).clearApiKey();
    state = ByokSettings(model: state.model);
  }
}

final byokSettingsProvider = NotifierProvider<ByokSettingsNotifier, ByokSettings>(
  ByokSettingsNotifier.new,
);
