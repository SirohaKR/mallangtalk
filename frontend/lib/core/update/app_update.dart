import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'app_reload_stub.dart' if (dart.library.js_interop) 'app_reload_web.dart' as platform;

/// 이 앱의 빌드 번호 (Dockerfile에서 --dart-define=BUILD_ID로 넣음, 개발·테스트 중에는 비어 있어 확인 안 함)
const appBuildId = String.fromEnvironment('BUILD_ID');

/// 서버에 올라간 최신 빌드 번호를 물어봄. 못 알아내면 null
Future<String?> fetchServerBuild({Dio? dio}) async {
  final url = platform.appBuildUrl();
  if (url == null) return null;
  final client = dio ??
      Dio(BaseOptions(
        receiveTimeout: const Duration(seconds: 10),
        responseType: ResponseType.plain,
      ));
  try {
    final response = await client.get<String>(
      url,
      queryParameters: {'t': '${DateTime.now().millisecondsSinceEpoch}'},
      options: Options(headers: {'cache-control': 'no-cache'}),
    );
    final data = jsonDecode(response.data ?? '');
    final build = data is Map ? data['build'] : null;
    return build is String && build.isNotEmpty ? build : null;
  } catch (_) {
    return null; // 개발 서버·플레이 링크처럼 파일이 없거나 연결이 안 됨
  }
}

/// [초보자 노트] 새 버전이 서버에 올라오면 앱이 알아서 바뀌게 하는 감시자예요.
/// - 앱을 켤 때, 다른 앱에 갔다가 돌아올 때, 켜 둔 채로 [checkEvery]마다 서버 빌드 번호를 확인해요.
/// - 켤 때 새 버전이면 바로 새로고침, 다른 앱에 갔다 돌아왔을 때 새 버전이면 그때 새로고침해요.
///   (보고 있는 화면 한가운데서는 갑자기 바뀌지 않고, 위에 '새 버전' 안내만 띄워요)
/// - 새로고침하기 전에 [beforeReload]로 아직 안 보낸 진행 상황을 서버에 보내요.
class AppUpdateWatcher extends StatefulWidget {
  const AppUpdateWatcher({
    super.key,
    required this.child,
    this.currentBuild = appBuildId,
    this.fetchBuild = fetchServerBuild,
    this.reload = platform.reloadApp,
    this.beforeReload,
    this.checkEvery = const Duration(minutes: 10),
  });

  final Widget child;
  final String currentBuild;
  final Future<String?> Function() fetchBuild;
  final void Function() reload;
  final Future<void> Function()? beforeReload;
  final Duration checkEvery;

  @override
  State<AppUpdateWatcher> createState() => _AppUpdateWatcherState();
}

class _AppUpdateWatcherState extends State<AppUpdateWatcher> with WidgetsBindingObserver {
  Timer? _timer;
  String? _newBuild;
  bool _hidden = false;
  bool _away = false;
  bool _checking = false;
  bool _reloading = false;
  bool _watching = false;

  @override
  void initState() {
    super.initState();
    if (widget.currentBuild.isEmpty) return;
    _watching = true;
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(widget.checkEvery, (_) => _check());
    WidgetsBinding.instance.addPostFrameCallback((_) => _check(reloadNow: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_watching) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
      _away = true;
    } else if (state == AppLifecycleState.resumed && _away) {
      // 다른 앱·탭에 갔다 돌아옴: 이때 새 버전이면 바로 바꿈 (폰 홈 화면 앱은 껐다 켜도 이 경우가 많음)
      _away = false;
      _check(reloadNow: true);
    }
  }

  Future<void> _check({bool reloadNow = false}) async {
    if (_checking || _reloading) return;
    _checking = true;
    try {
      final latest = await widget.fetchBuild();
      if (!mounted || latest == null || latest == widget.currentBuild) return;
      if (reloadNow && !platform.triedReloadFor(latest)) {
        await _reload(latest);
      } else if (_newBuild != latest) {
        // 새로고침했는데도 예전 버전이 떴거나, 보는 중에 새 버전이 나옴 → 안내만
        setState(() {
          _newBuild = latest;
          _hidden = false;
        });
      }
    } finally {
      _checking = false;
    }
  }

  Future<void> _reload(String build) async {
    if (_reloading) return;
    _reloading = true;
    platform.markReloadFor(build);
    final beforeReload = widget.beforeReload;
    if (beforeReload != null) {
      try {
        await beforeReload().timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    widget.reload();
    // 새로고침이 안 된 경우(웹이 아님 등) 다시 누를 수 있게
    _reloading = false;
  }

  @override
  Widget build(BuildContext context) {
    final build = _newBuild;
    if (build == null || _hidden) return widget.child;
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 12,
          right: 12,
          top: MediaQuery.paddingOf(context).top + 8,
          child: _UpdateBanner(
            onUpdate: () => _reload(build),
            onClose: () => setState(() => _hidden = true),
          ),
        ),
      ],
    );
  }
}

class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({required this.onUpdate, required this.onClose});

  final VoidCallback onUpdate;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Material(
          color: AppColors.surfaceWhite,
          elevation: 4,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, size: 18, color: AppColors.primaryPink),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('새 버전이 나왔어요', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                ),
                TextButton(onPressed: onUpdate, child: const Text('지금 업데이트')),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
