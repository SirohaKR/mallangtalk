{{flutter_js}}
{{flutter_build_config}}

// 서비스 워커를 쓰지 않음: 예전 파일을 붙잡고 있어 새 버전이 늦게 반영되는 걸 막음
// (새 버전 확인·새로고침은 앱 안의 AppUpdateWatcher가 함)
_flutter.loader.load();
