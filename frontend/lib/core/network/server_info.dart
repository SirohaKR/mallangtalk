import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ai_provider.dart';
import 'api_endpoint.dart';

/// 말랑톡 서버에서 앱을 열었을 때 서버가 알려 준 정보 (키 자체는 절대 안 옴)
class ServerInfo {
  /// 앱을 띄운 서버 주소 (예: http://192.168.0.10:5200)
  final String baseUrl;

  /// 서버 .env에 키가 들어 있는 AI 회사
  final Set<AiProvider> providers;

  /// 서버에 ACCESS_CODE가 정해져 있으면 true
  final bool needsAccessCode;

  /// 계정(로그인·회원가입)과 캐릭터 저장을 지원하는 서버인지
  final bool accounts;

  const ServerInfo({
    required this.baseUrl,
    required this.providers,
    this.needsAccessCode = false,
    this.accounts = false,
  });
}

/// [초보자 노트] 앱이 켜질 때 '지금 이 화면을 띄운 곳이 말랑톡 서버인지' 한 번 물어봐요.
/// claude.ai 플레이 링크처럼 서버가 없는 곳에서는 null이 되고, 그때는 예전처럼 내 키(BYOK)를 씁니다.
final serverInfoProvider = FutureProvider<ServerInfo?>((ref) => detectServer(Uri.base));

Future<ServerInfo?> detectServer(Uri page, {Dio? dio}) async {
  if (!kIsWeb && dio == null && configuredApiBaseUrl.isEmpty) return null;
  final origin = apiOrigin(page);
  if (origin == null) return null;
  final client = dio ??
      Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 3),
        receiveTimeout: const Duration(seconds: 3),
      ));
  try {
    final response = await client.get<Map<String, dynamic>>('${origin.origin}/api/health');
    final data = response.data;
    if (data == null || data['ok'] != true) return null;
    return ServerInfo(
      baseUrl: origin.origin,
      providers: {
        for (final name in data['providers'] as List? ?? const [])
          if (AiProvider.values.where((p) => p.name == name).firstOrNull case final p?) p,
      },
      needsAccessCode: data['needsAccessCode'] == true,
      accounts: data['accounts'] == true,
    );
  } catch (_) {
    return null; // 서버가 아니거나(정적 호스팅·플레이 링크) 연결이 막힘
  }
}
