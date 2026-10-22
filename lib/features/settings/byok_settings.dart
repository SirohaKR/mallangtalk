import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/ai_provider.dart';
import '../../core/storage/local_store.dart';

/// 내 AI 키(BYOK) 설정 상태: 고른 AI 회사, 그 회사의 키와 모델
class ByokSettings {
  final AiProvider provider;
  final String? apiKey;
  final String model;

  const ByokSettings({this.provider = AiProvider.claude, this.apiKey, required this.model});

  bool get hasKey => apiKey != null && apiKey!.isNotEmpty;

  /// 화면에 보여줄 때는 키 앞뒤 몇 글자만
  String get maskedKey {
    final key = apiKey ?? '';
    if (key.length <= 12) return '••••';
    return '${key.substring(0, 7)}••••${key.substring(key.length - 4)}';
  }

  /// 목록에 있는 모델이면 이름·가격 정보 (직접 입력한 모델이면 null)
  AiModelOption? get modelOption => provider.option(model);
}

/// [초보자 노트] 설정 화면과 채팅방·만들기 화면이 함께 보는 BYOK 설정 보관함입니다.
/// 키는 AI 회사마다 따로 이 브라우저(localStorage)에만 저장되고, 서버로 따로 보내지 않습니다.
class ByokSettingsNotifier extends Notifier<ByokSettings> {
  @override
  ByokSettings build() {
    final store = ref.watch(localStoreProvider);
    return _load(store, AiProvider.byName(store.provider));
  }

  ByokSettings _load(LocalStore store, AiProvider provider) => ByokSettings(
        provider: provider,
        apiKey: store.apiKeyOf(provider.name),
        model: store.modelOf(provider.name) ?? provider.defaultModel,
      );

  /// 설정 화면에서 다른 회사를 골랐을 때 그 회사에 저장해 둔 키·모델 (저장은 안 함)
  ByokSettings peek(AiProvider provider) => _load(ref.read(localStoreProvider), provider);

  Future<void> save({required AiProvider provider, required String apiKey, required String model}) async {
    await ref.read(localStoreProvider)
        .saveByok(provider: provider.name, apiKey: apiKey.trim(), model: model.trim());
    state = ByokSettings(provider: provider, apiKey: apiKey.trim(), model: model.trim());
  }

  Future<void> removeKey(AiProvider provider) async {
    await ref.read(localStoreProvider).clearApiKey(provider.name);
    if (state.provider == provider) state = ByokSettings(provider: provider, model: state.model);
  }
}

final byokSettingsProvider = NotifierProvider<ByokSettingsNotifier, ByokSettings>(
  ByokSettingsNotifier.new,
);
