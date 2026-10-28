import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/ai_provider.dart';
import '../../core/network/server_info.dart';
import '../../core/storage/local_store.dart';

/// AI 설정 상태: 고른 AI 회사, 그 회사의 내 키와 모델, 그리고 말랑톡 서버에서 열었는지
class ByokSettings {
  final AiProvider provider;
  final String? apiKey;
  final String model;

  /// 말랑톡 서버에서 앱을 열었으면 서버 정보 (아니면 null)
  final ServerInfo? server;

  /// 서버 접속 코드 (서버가 요구할 때만)
  final String? accessCode;

  const ByokSettings({
    this.provider = AiProvider.claude,
    this.apiKey,
    required this.model,
    this.server,
    this.accessCode,
  });

  bool get hasKey => apiKey != null && apiKey!.isNotEmpty;

  /// 서버 .env에 고른 회사 키가 있으면 내 키 대신 서버로 부름 (브라우저에 키를 안 둬도 됨)
  bool get usesServer => server?.providers.contains(provider) ?? false;

  /// 자유대화·AI로 만들기를 쓸 수 있는지
  bool get canUseAi => usesServer || hasKey;

  /// AI를 서버로 부를 때 쓸 주소·접속 코드 (내 키로 부르면 null)
  AiRelay? get relay => usesServer ? AiRelay(server!.baseUrl, accessCode: accessCode) : null;

  /// 화면에 보여줄 때는 키 앞뒤 몇 글자만
  String get maskedKey {
    final key = apiKey ?? '';
    if (key.length <= 12) return '••••';
    return '${key.substring(0, 7)}••••${key.substring(key.length - 4)}';
  }

  /// 목록에 있는 모델이면 이름·가격 정보 (직접 입력한 모델이면 null)
  AiModelOption? get modelOption => provider.option(model);
}

/// [초보자 노트] 설정 화면과 채팅방·만들기 화면이 함께 보는 AI 설정 보관함입니다.
/// 내 키는 AI 회사마다 따로 이 브라우저(localStorage)에만 저장돼요.
/// 말랑톡 서버에서 열었고 서버에 그 회사 키가 있으면 내 키 없이 서버가 대신 불러 줍니다.
class ByokSettingsNotifier extends Notifier<ByokSettings> {
  @override
  ByokSettings build() {
    final store = ref.watch(localStoreProvider);
    final server = ref.watch(serverInfoProvider).valueOrNull; // 서버 확인이 끝나면 다시 읽음
    return _load(store, _initialProvider(store, server));
  }

  /// 아직 회사를 고른 적 없으면: 서버 키가 있는 회사 → 예전에 넣어 둔 Claude 키 → 무료 한도가 있는 Gemini
  static AiProvider _initialProvider(LocalStore store, ServerInfo? server) {
    if (store.provider != null) return AiProvider.byName(store.provider);
    final serverFirst = AiProvider.values.where((p) => server?.providers.contains(p) ?? false).firstOrNull;
    if (serverFirst != null) return serverFirst;
    if (store.apiKeyOf(AiProvider.claude.name)?.isNotEmpty ?? false) return AiProvider.claude;
    return AiProvider.gemini;
  }

  ByokSettings _load(LocalStore store, AiProvider provider) => ByokSettings(
        provider: provider,
        apiKey: store.apiKeyOf(provider.name),
        model: store.modelOf(provider.name) ?? provider.defaultModel,
        server: ref.read(serverInfoProvider).valueOrNull,
        accessCode: store.serverAccessCode,
      );

  /// 설정 화면에서 다른 회사를 골랐을 때 그 회사에 저장해 둔 키·모델 (저장은 안 함)
  ByokSettings peek(AiProvider provider) => _load(ref.read(localStoreProvider), provider);

  /// [apiKey]가 비어 있으면 저장해 둔 키는 그대로 두고 회사·모델만 바꿈 (서버 키를 쓸 때)
  Future<void> save({required AiProvider provider, required String apiKey, required String model}) async {
    final store = ref.read(localStoreProvider);
    final key = apiKey.trim().isNotEmpty ? apiKey.trim() : (store.apiKeyOf(provider.name) ?? '');
    await store.saveByok(provider: provider.name, apiKey: key, model: model.trim());
    state = _load(store, provider);
  }

  Future<void> removeKey(AiProvider provider) async {
    final store = ref.read(localStoreProvider);
    await store.clearApiKey(provider.name);
    if (state.provider == provider) state = _load(store, provider);
  }

  Future<void> saveAccessCode(String code) async {
    final store = ref.read(localStoreProvider);
    await store.saveServerAccessCode(code.trim());
    state = _load(store, state.provider);
  }
}

final byokSettingsProvider = NotifierProvider<ByokSettingsNotifier, ByokSettings>(
  ByokSettingsNotifier.new,
);

/// AI 회사별 API 키 발급 페이지
String aiKeyPage(AiProvider provider) => switch (provider) {
      AiProvider.gemini => 'https://aistudio.google.com/apikey',
      AiProvider.claude => 'https://console.anthropic.com/settings/keys',
      AiProvider.openai => 'https://platform.openai.com/api-keys',
    };

/// 'Claude (Anthropic)' → 'Claude'
String aiShortName(AiProvider provider) => provider.label.split(' (').first;

/// 대화방에 보여 줄 모델 이름 (목록에 없으면 직접 입력한 이름 그대로)
String aiModelName(ByokSettings s) => s.modelOption?.label ?? s.model;
