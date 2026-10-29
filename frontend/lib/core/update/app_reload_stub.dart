/// 웹이 아닐 때(테스트·앱 빌드): 새 버전 확인을 하지 않음
String? appBuildUrl() => null;

String? _reloadedFor;

/// 이 탭에서 [build]로 바꾸려고 이미 새로고침했는지
bool triedReloadFor(String build) => _reloadedFor == build;

void markReloadFor(String build) => _reloadedFor = build;

void reloadApp() {}
