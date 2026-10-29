import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// 지금 서버에 올라간 앱 빌드 번호 파일 (Dockerfile이 만듦). <base href> 기준이라 어느 화면에서든 같은 곳
String? appBuildUrl() => Uri.parse(web.document.baseURI).resolve('app_build.json').toString();

const _reloadKey = 'mallang_reloaded_for';

/// 이 탭에서 [build]로 바꾸려고 이미 새로고침했는지 (새로고침이 계속 반복되지 않게)
bool triedReloadFor(String build) {
  try {
    return web.window.sessionStorage.getItem(_reloadKey) == build;
  } catch (_) {
    return false;
  }
}

void markReloadFor(String build) {
  try {
    web.window.sessionStorage.setItem(_reloadKey, build);
  } catch (_) {}
}

@JS('mallangReload')
external void _mallangReload();

/// index.html의 mallangReload: 예전 서비스 워커·캐시를 지우고 새로고침
void reloadApp() {
  try {
    _mallangReload();
  } catch (_) {
    web.window.location.reload();
  }
}
