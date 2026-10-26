import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/mallangtalk_api.dart';
import '../../core/network/server_info.dart';
import '../../core/storage/local_store.dart';

/// 로그인 상태 (토큰이 있으면 로그인됨)
class AuthState {
  final String? token;
  final AccountUser? user;
  const AuthState({this.token, this.user});

  bool get isLoggedIn => token != null && user != null;
}

/// [초보자 노트] 아이디·비밀번호 로그인 상태입니다. 로그인 표(토큰)는 이 브라우저에 저장돼서
/// 새로고침해도 로그인이 유지돼요. 서버 없이 연 플레이 링크에서는 쓰지 않아요.
class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    final store = ref.watch(localStoreProvider);
    final token = store.authToken;
    final userJson = store.authUserJson;
    if (token == null || userJson == null) return const AuthState();
    try {
      return AuthState(token: token, user: AccountUser.fromJson(jsonDecode(userJson) as Map));
    } catch (_) {
      return const AuthState();
    }
  }

  MallangtalkApi? get _api {
    final server = ref.read(serverInfoProvider).valueOrNull;
    return server == null ? null : ref.read(apiFactoryProvider)(server.baseUrl, null);
  }

  Future<void> login(String username, String password) async {
    final api = _api;
    if (api == null) throw const ApiException('서버에 연결하지 못했어요.');
    final (token, user) = await api.login(username.trim(), password);
    await _save(token, user);
  }

  Future<void> signup(String username, String password, String nickname) async {
    final api = _api;
    if (api == null) throw const ApiException('서버에 연결하지 못했어요.');
    final (token, user) = await api.signup(username.trim(), password, nickname.trim());
    await _save(token, user);
  }

  Future<void> logout() async {
    final token = state.token;
    final server = ref.read(serverInfoProvider).valueOrNull;
    if (token != null && server != null) {
      try {
        await ref.read(apiFactoryProvider)(server.baseUrl, token).logout();
      } catch (_) {
        // 서버가 꺼져 있어도 이 브라우저에서는 로그아웃
      }
    }
    await ref.read(localStoreProvider).saveAuth(null, null);
    state = const AuthState();
  }

  /// 내 프로필(별명·사진·소개)을 서버에도 올려서 다른 사람이 보는 제작자 프로필이 따라가게 해요.
  /// 로그인 전이거나 서버가 없으면 아무것도 하지 않아요.
  Future<void> pushProfile({String? nickname, String? avatarUrl, String? intro}) async {
    final api = ref.read(accountApiProvider);
    final token = state.token;
    if (api == null || token == null) return;
    final user = await api.updateProfile(nickname: nickname, avatarUrl: avatarUrl, intro: intro);
    await _save(token, user);
  }

  Future<void> _save(String token, AccountUser user) async {
    await ref.read(localStoreProvider).saveAuth(token, jsonEncode(user.toJson()));
    state = AuthState(token: token, user: user);
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

/// 로그인한 상태로 서버 API를 부를 클라이언트 (서버가 없거나 로그인 전이면 null)
final accountApiProvider = Provider<MallangtalkApi?>((ref) {
  final server = ref.watch(serverInfoProvider).valueOrNull;
  final auth = ref.watch(authProvider);
  if (server == null || !server.accounts || !auth.isLoggedIn) return null;
  return ref.watch(apiFactoryProvider)(server.baseUrl, auth.token);
});

/// 서버 API 클라이언트 만드는 법 (테스트에서 가짜로 바꿔 끼움)
final apiFactoryProvider = Provider<MallangtalkApi Function(String baseUrl, String? token)>(
  (ref) => (baseUrl, token) => MallangtalkApi(baseUrl: baseUrl, token: token),
);
