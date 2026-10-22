import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/claude_chat_client.dart';
import '../../core/network/claude_studio_client.dart';
import '../../core/storage/local_store.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/models/mallangtalk_models.dart';
import '../../shared/utils/file_io.dart';
import '../../shared/widgets/character_avatar.dart';
import '../add/add_character_screen.dart';
import '../chat/chat_notifier.dart';
import '../library/character_library.dart';
import '../settings/byok_settings.dart';
import 'character_import.dart';
import 'scenario_draft.dart';
import 'studio_widgets.dart';
import 'template_scenario.dart';

/// [초보자 노트] 캐릭터 만들기(편집기) 화면입니다. 엑셀 없이 앱 안에서 전부 만듭니다.
/// 탭: 캐릭터 / 호감도 단계 / 이벤트 / 대사
/// - 'AI로 만들기'를 누르면 캐릭터 탭에 적은 설정을 토대로 이벤트·일상 대화·특별 이벤트·엔딩과 모든 대사를 채워 줍니다.
/// - 직접 만들 때는 이벤트 탭에서 대화를 추가하고, 대사 탭에서 장면·말풍선·선택지를 하나씩 넣습니다.
/// - 이벤트 하나만 골라서 'AI로 대사 쓰기'를 해도 돼요.
/// initial을 주면 이미 만든 캐릭터를 고치는 화면이 됩니다.
/// 내 캐릭터를 고치는 화면 (/edit/캐릭터ID)
class EditCharacterPage extends ConsumerWidget {
  const EditCharacterPage({super.key, required this.characterId});

  final String characterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bundle = ref.read(characterBundleProvider(characterId));
    if (bundle == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('캐릭터를 찾을 수 없어요')));
    }
    return StudioScreen(initial: bundle);
  }
}

class StudioScreen extends ConsumerStatefulWidget {
  const StudioScreen({super.key, this.initial});

  final ScenarioBundle? initial;

  @override
  ConsumerState<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends ConsumerState<StudioScreen>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  late ScenarioDraft _draft;
  late final TabController _tabs = TabController(length: 4, vsync: this);
  /// 초안을 통째로 바꿀 때마다 올려서 입력칸을 새로 채움
  int _version = 0;
  EventDraft? _scriptEvent;

  bool _generating = false;
  String _progressText = '';
  double _progress = 0;
  int _eventsPerStage = 2;
  int _dailiesPerStage = 3;
  int _specials = 1;

  bool get _editing => widget.initial != null;

  @override
  bool get wantKeepAlive => true; // 탭을 옮겨도 쓰던 내용 유지

  @override
  void initState() {
    super.initState();
    _draft = widget.initial != null ? ScenarioDraft.fromBundle(widget.initial!) : _savedDraft() ?? ScenarioDraft.blank();
    // 새 캐릭터를 만드는 중이면 몇 초마다 브라우저에 초안을 저장 (새로고침해도 이어 쓰기)
    if (widget.initial == null) {
      _autosave = Timer.periodic(const Duration(seconds: 3), (_) => _saveDraftNow());
    }
  }

  @override
  void dispose() {
    _autosave?.cancel();
    if (widget.initial == null) _saveDraftNow();
    _tabs.dispose();
    super.dispose();
  }

  Timer? _autosave;
  String? _lastSavedDraft;

  ScenarioDraft? _savedDraft() {
    final raw = ref.read(localStoreProvider).loadStudioDraft();
    if (raw == null) return null;
    try {
      _lastSavedDraft = raw;
      return ScenarioDraft.fromBundle(ScenarioBundle.fromJson(jsonDecode(raw) as Map<String, dynamic>));
    } catch (_) {
      return null; // 형식이 바뀐 옛 초안은 무시
    }
  }

  void _saveDraftNow() {
    try {
      final json = jsonEncode(_draft.toBundle().toJson());
      if (json == _lastSavedDraft) return;
      _lastSavedDraft = json;
      ref.read(localStoreProvider).saveStudioDraft(json);
    } catch (_) {
      // 쓰다 만 초안이라 묶지 못해도 다음 저장 때 다시 시도
    }
  }

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  void _replaceDraft(ScenarioDraft draft) => setState(() {
        _draft = draft;
        _version++;
        _scriptEvent = null;
        _charPage = 0;
      });

  String _k(Object owner, String field) => '$_version-${identityHashCode(owner)}-$field';

  Future<bool> _confirm(String title, String body, String ok) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
        ],
      ),
    );
    return result == true;
  }

  // ───────────────────────── 메뉴 ─────────────────────────

  Future<void> _onMenu(String action) async {
    switch (action) {
      case 'new':
        if (await _confirm('새로 만들기', '지금 적은 내용이 지워져요.', '새로 만들기')) {
          _replaceDraft(ScenarioDraft.blank());
        }
      case 'example':
        if (await _confirm('예시 불러오기', '예시 캐릭터 서이준으로 채워요. 지금 적은 내용은 지워져요.', '불러오기')) {
          _replaceDraft(ScenarioDraft.fromBundle(templateScenario())..id = 'char_${DateTime.now().millisecondsSinceEpoch}');
        }
      case 'example_kaien':
        if (await _confirm('카이엔 불러오기', '로판 아카데미 황자님 카이엔의 캐릭터 설정(8쪽)과 호감도 단계 5개로 채워요. 지금 적은 내용은 지워져요.', '불러오기')) {
          _replaceDraft(ScenarioDraft.fromBundle(kaienScenario()));
        }
      case 'import':
        final file = await FileIO.pick(extensions: ['json']);
        if (file == null) return;
        try {
          _replaceDraft(ScenarioDraft.fromBundle(readCharacterFile(file)));
          _toast('캐릭터 파일을 불러왔어요');
        } on FormatException catch (e) {
          _toast(e.message);
        }
      case 'export':
        final bundle = _draft.toBundle();
        await FileIO.save(
          fileName: '${FileIO.safeName(_draft.name.isEmpty ? '캐릭터' : _draft.name)}.json',
          bytes: utf8.encode(const JsonEncoder.withIndent('  ').convert(bundle.toJson())),
          mimeType: FileIO.jsonMime,
        );
    }
  }

  // ───────────────────────── AI ─────────────────────────

  bool _readyForAi() {
    if (_draft.name.trim().isEmpty) {
      _toast('캐릭터 탭에서 이름을 먼저 적어 주세요');
      _tabs.animateTo(0);
      _goCharPage(0);
      return false;
    }
    if (_draft.setting.trim().length < 10) {
      _toast('캐릭터 설정(성격·말투·취미)을 조금 더 자세히 적어 주세요');
      _tabs.animateTo(0);
      _goCharPage(2);
      return false;
    }
    final stageProblems = _draft.problems().where((p) => p.startsWith('[호감도 단계]')).toList();
    if (stageProblems.isNotEmpty) {
      _toast(stageProblems.first);
      _tabs.animateTo(1);
      return false;
    }
    if (!ref.read(byokSettingsProvider).canUseAi) {
      _toast('설정에서 AI 키를 먼저 넣어 주세요');
      return false;
    }
    return true;
  }

  Future<void> _openAiSheet() async {
    if (!_readyForAi()) return;
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceWhite,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          void update(VoidCallback f) {
            setState(f);
            setSheet(() {});
          }

          final total = _draft.stageNames.length * (_eventsPerStage + _dailiesPerStage) + _specials + 1;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('AI로 이벤트·대사 만들기', style: AppTextStyles.appBarTitle),
                  const SizedBox(height: 6),
                  const Text(
                    '캐릭터 탭의 설정과 호감도 단계를 보고 목차와 모든 대사를 써요. '
                    '비어 있는 캐릭터 정보(한줄 소개·태그·세계관·캐릭터 정보)도 채워 줘요. '
                    '지금 이벤트 탭에 있는 대화는 새로 만든 것으로 바뀌어요.',
                    style: AppTextStyles.systemNotice,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  StudioCounter(
                    label: '단계마다 호감도 이벤트',
                    value: _eventsPerStage,
                    min: 1,
                    max: 5,
                    onChanged: (v) => update(() => _eventsPerStage = v),
                  ),
                  StudioCounter(
                    label: '단계마다 일상 대화',
                    value: _dailiesPerStage,
                    min: 0,
                    max: 6,
                    onChanged: (v) => update(() => _dailiesPerStage = v),
                  ),
                  StudioCounter(
                    label: '특별 이벤트 (실제 시간)',
                    value: _specials,
                    min: 0,
                    max: 4,
                    onChanged: (v) => update(() => _specials = v),
                  ),
                  const SizedBox(height: 4),
                  Text('대화 $total개 · 대화 수만큼 AI를 불러요 (내 키 사용)', style: AppTextStyles.messageTime),
                  const SizedBox(height: AppSpacing.md),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: const Text('만들기 시작'),
                    onPressed: () => Navigator.pop(sheetContext, true),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (go == true) await _generateAll();
  }

  Future<void> _generateAll() async {
    final byok = ref.read(byokSettingsProvider);
    setState(() {
      _generating = true;
      _progress = 0;
      _progressText = '시작하는 중';
    });
    try {
      final bundle = await ref.read(claudeStudioClientProvider).generate(
            provider: byok.provider,
            apiKey: byok.apiKey ?? '',
            relay: byok.relay,
            model: byok.model,
            brief: StudioBrief(
              character: _draft.buildCharacter(),
              eventsPerStage: _eventsPerStage,
              dailiesPerStage: _dailiesPerStage,
              specials: _specials,
            ),
            onProgress: (message, done, total) {
              if (!mounted) return;
              setState(() {
                _progressText = message;
                _progress = total == 0 ? 0 : done / total;
              });
            },
          );
      if (!mounted) return;
      _replaceDraft(ScenarioDraft.fromBundle(bundle));
      _tabs.animateTo(2);
      _toast('이벤트 ${bundle.events.length}개를 만들었어요. 고칠 곳을 고친 뒤 저장해 주세요');
    } on ClaudeChatException catch (e) {
      if (mounted) _toast(e.message);
    } catch (e) {
      if (mounted) _toast('만드는 중 문제가 생겼어요: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  /// 이벤트 하나의 대사만 AI로 쓰기 (제목·줄거리 메모를 보고)
  Future<void> _generateOne(EventDraft event) async {
    if (!_readyForAi()) return;
    if (event.title.trim().isEmpty) return _toast('이벤트 제목을 먼저 적어 주세요');
    final hasLines = event.scenes.any((s) => s.lines.any((l) => l.text.trim().isNotEmpty));
    if (hasLines && !await _confirm('AI로 대사 쓰기', '"${event.title}"에 적은 대사가 새로 쓴 것으로 바뀌어요.', '새로 쓰기')) {
      return;
    }
    final byok = ref.read(byokSettingsProvider);
    setState(() {
      _generating = true;
      _progress = 0.3;
      _progressText = '"${event.title}" 대사를 쓰는 중';
    });
    try {
      final character = _draft.buildCharacter();
      final all = [for (var i = 0; i < _draft.events.length; i++) _draft.buildEvent(_draft.events[i], i)];
      final model = all[_draft.events.indexOf(event)];
      final (nodes, step) = await ref.read(claudeStudioClientProvider).writeScript(
            provider: byok.provider,
            apiKey: byok.apiKey ?? '',
            relay: byok.relay,
            model: byok.model,
            character: character,
            event: model,
            outline: all,
          );
      if (!mounted) return;
      final filled = ScenarioDraft.eventFromBundle(
        ScenarioBundle(character: character, events: const [], nodes: const {}),
        model.withCutsceneStep(model.cutscenePhotoTitle != null ? step : null),
        nodes: nodes,
      );
      setState(() {
        event.scenes
          ..clear()
          ..addAll(filled.scenes);
        _version++;
        _scriptEvent = event;
      });
      _tabs.animateTo(3);
    } on ClaudeChatException catch (e) {
      if (mounted) _toast(e.message);
    } catch (e) {
      if (mounted) _toast('대사를 쓰는 중 문제가 생겼어요: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  // ───────────────────────── 저장 ─────────────────────────

  Future<void> _save() async {
    final problems = _draft.problems();
    if (problems.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('고칠 곳이 있어요'),
          content: SingleChildScrollView(child: ProblemList(title: '저장하기 전에', items: problems, isError: true)),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('확인'))],
        ),
      );
      return;
    }
    var bundle = _draft.toBundle();
    if (!bestPathClears(bundle)) {
      final fix = await _confirm(
        '호감도 자동으로 맞추기',
        '좋은 선택만 골라도 다음 단계 점수에 못 가서 막히는 이벤트가 있어요. 선택지 호감도를 조금씩 올려서 맞출까요?',
        '맞추기',
      );
      if (fix) bundle = balanceScenario(bundle);
    }
    final library = ref.read(characterLibraryProvider.notifier);
    final existing = library.byId(bundle.character.id);
    await library.add(
      bundle,
      existing?.source == CharacterSource.imported ? CharacterSource.imported : CharacterSource.created,
    );
    ref.invalidate(chatRoomProvider(bundle.character.id));
    if (!mounted) return;
    if (_editing) {
      Navigator.of(context).pop();
      _toast('${bundle.character.name} 수정 내용을 저장했어요');
    } else {
      _toast('${bundle.character.name}을(를) 내 캐릭터에 저장했어요. 내 캐릭터에서 대화를 시작해 보세요');
      _replaceDraft(ScenarioDraft.blank());
      _tabs.animateTo(0);
    }
  }

  // ───────────────────────── 화면 ─────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final body = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.mobileMaxWidth),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TabBar(
                    controller: _tabs,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    labelStyle: AppTextStyles.choiceButton.copyWith(fontSize: 13),
                    unselectedLabelStyle:
                        AppTextStyles.choiceButton.copyWith(fontSize: 13, color: AppColors.textSecondary),
                    indicatorColor: AppColors.primaryPink,
                    tabs: const [Tab(text: '캐릭터'), Tab(text: '호감도 단계'), Tab(text: '이벤트'), Tab(text: '대사')],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: '더 보기',
                  onSelected: _onMenu,
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'new', child: Text('새로 만들기')),
                    PopupMenuItem(value: 'example', child: Text('예시 캐릭터 불러오기')),
                    PopupMenuItem(value: 'example_kaien', child: Text('예시: 카이엔 (설정만)')),
                    PopupMenuItem(value: 'import', child: Text('캐릭터 파일(.json) 불러오기')),
                    PopupMenuItem(value: 'export', child: Text('캐릭터 파일로 내보내기')),
                  ],
                ),
              ],
            ),
            if (_generating)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LinearProgressIndicator(value: _progress, color: AppColors.aiActivePurple),
                    const SizedBox(height: 4),
                    Text(_progressText, style: AppTextStyles.messageTime),
                  ],
                ),
              ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _characterTab(),
                  _stagesTab(),
                  _eventsTab(),
                  _scriptTab(),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
              decoration: const BoxDecoration(
                color: AppColors.surfaceWhite,
                border: Border(top: BorderSide(color: AppColors.borderLight)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                      label: const Text('AI로 만들기'),
                      onPressed: _generating ? null : _openAiSheet,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: Text(_editing ? '수정 저장' : '저장'),
                      onPressed: _generating ? null : _save,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (!_editing) return body;
    return Scaffold(
      appBar: AppBar(title: Text('${widget.initial!.character.name} 고치기')),
      body: body,
    );
  }

  // ───────────────────────── 캐릭터 탭 ─────────────────────────

  /// 캐릭터 탭은 한 화면에 한 항목씩, 화살표로 넘김 (긴 설정을 넓은 칸에 쓰도록)
  int _charPage = 0;

  static const _charPages = [
    ('기본 정보', '갤러리 카드와 채팅방에 보이는 것들'),
    ('캐릭터 정보', '나이, 직업, 생일처럼 짧은 항목. 자물쇠를 켜면 플레이어에겐 숨겨요'),
    ('캐릭터 설정', '성격, 말투 습관(ㅋㅋ를 자주 씀 등), 취미, 관심사, 나와의 사이. 자세할수록 AI가 잘 따라 해요. 상세 화면에 그대로 보여요'),
    ('세계관 설정', '이야기의 배경이 되는 곳·시대·분위기. 상세 화면에 보여요. 비우면 AI가 채워 줘요'),
    ('나는 이 이야기에서', '플레이어가 누구인지. {{user}}는 플레이어 별명, {{char}}는 캐릭터 이름으로 바뀌어요. 상세 화면에 보여요'),
    ('주변 인물', '대화에 이름이 나오는 친구·가족·반려동물. 상세 화면에 보여요'),
    ('비밀 설정', '플레이어에겐 안 보이고, 이야기와 AI 자유대화가 서서히 드러내요'),
    ('말투와 타자 스타일', '제작자와 AI만 보는 말투 참고용'),
  ];

  void _goCharPage(int page) {
    FocusScope.of(context).unfocus();
    setState(() => _charPage = page.clamp(0, _charPages.length - 1));
  }

  Widget _characterTab() {
    final (title, note) = _charPages[_charPage];
    final last = _charPages.length - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('${_charPage + 1}/${_charPages.length}', style: AppTextStyles.messageTime),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(title, style: AppTextStyles.appBarTitle.copyWith(fontSize: 17))),
              if (_charPage >= 1 && _charPage <= 5)
                const Text('플레이어에게 보임', style: AppTextStyles.messageTime),
            ],
          ),
          const SizedBox(height: 4),
          Text(note, style: AppTextStyles.systemNotice),
          const SizedBox(height: AppSpacing.sm),
          // 몇 번째 항목인지 점으로 (눌러서 바로 이동)
          Row(
            children: [
              for (var i = 0; i < _charPages.length; i++)
                Expanded(
                  child: GestureDetector(
                    onTap: () => _goCharPage(i),
                    child: Container(
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: i <= _charPage ? AppColors.primaryPink : AppColors.borderLight,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(child: _charPageBody(_charPage)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: Text(_charPage == 0 ? '이전' : _charPages[_charPage - 1].$1, overflow: TextOverflow.ellipsis),
                  onPressed: _charPage == 0 ? null : () => _goCharPage(_charPage - 1),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _charPage == last ? _tabs.animateTo(1) : _goCharPage(_charPage + 1),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          _charPage == last ? '호감도 단계로' : _charPages[_charPage + 1].$1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _charPageBody(int page) {
    final d = _draft;
    switch (page) {
      case 0:
        final preview = d.buildCharacter();
        return ListView(
          children: [
            Row(
              children: [
                CharacterAvatar(character: preview, radius: 34),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.photo_camera_outlined, size: 18),
                        label: Text(d.avatarUrl.isEmpty ? '프로필 사진 고르기' : '사진 바꾸기'),
                        onPressed: () async {
                          final image = await pickProfileImage();
                          if (image != null) setState(() => d.avatarUrl = image);
                        },
                      ),
                      const Text('갤러리 썸네일과 채팅방에 보여요', style: AppTextStyles.messageTime),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            EditField(fieldKey: _k(d, 'name'), value: d.name, label: '이름', hint: '예: 윤도하', maxLength: 20,
                onChanged: (v) => setState(() => d.name = v)),
            EditField(fieldKey: _k(d, 'tagline'), value: d.tagline, label: '한줄 소개',
                hint: '갤러리 카드에 보여요. 비우면 AI가 지어 줘요', lines: 2, onChanged: (v) => d.tagline = v),
            EditField(fieldKey: _k(d, 'tags'), value: d.tags, label: '태그',
                hint: '쉼표로 구분. 예: 남사친, 장난꾸러기, 고양이집사', onChanged: (v) => d.tags = v),
            EditField(fieldKey: _k(d, 'status'), value: d.statusMessage, label: '상태메시지',
                hint: '채팅방 이름 아래 보여요', onChanged: (v) => d.statusMessage = v),
          ],
        );
      case 1:
        return ListView(children: [_fieldsEditor()]);
      case 2:
        return BigTextField(
          fieldKey: _k(d, 'setting'),
          value: d.setting,
          hint: '예) 1년 전 교양 수업 팀플에서 만나 거의 매일 연락하는 남사친. 장난기 많고 ㅋㅋ를 달고 산다. '
              '진지해지면 말이 짧아지고 띄어쓰기가 정확해진다. 주말 새벽엔 한강을 뛰고…',
          onChanged: (v) => d.setting = v,
        );
      case 3:
        return BigTextField(
          fieldKey: _k(d, 'world'),
          value: d.world,
          hint: '예) 지금의 서울. 홍대 근처 대학가에서 자취하는 대학생들의 평범한 봄~여름…',
          onChanged: (v) => d.world = v,
        );
      case 4:
        return BigTextField(
          fieldKey: _k(d, 'role'),
          value: d.userRole,
          hint: '예) {{user}} · 1년 전 교양 수업 팀플에서 {{char}}와 만난 친구. 거의 매일 연락하는 사이',
          onChanged: (v) => d.userRole = v,
        );
      case 5:
        return ListView(children: [_castEditor()]);
      case 6:
        return BigTextField(
          fieldKey: _k(d, 'secret'),
          value: d.secret,
          hint: '예) 사실 처음 만난 날부터 좋아했다. 친구 사이가 깨질까 봐 장난으로 넘겨 왔다…',
          onChanged: (v) => d.secret = v,
        );
      default:
        return ListView(
          children: [
            EditField(fieldKey: _k(d, 'quote'), value: d.quote, label: '대표 대사',
                hint: '이 캐릭터다운 한 마디. 비우면 AI가 지어 줘요', lines: 2, onChanged: (v) => d.quote = v),
            const Text('타자 스타일', style: AppTextStyles.speakerName),
            const SizedBox(height: 6),
            TypingStylePicker(value: d.typing, onChanged: (v) => setState(() => d.typing = v)),
          ],
        );
    }
  }

  Widget _fieldsEditor() {
    final d = _draft;
    return StudioCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final f in d.fields)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 92,
                    child: EditField(fieldKey: _k(f, 'label'), value: f.label, hint: '항목', dense: true,
                        onChanged: (v) => f.label = v),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: EditField(fieldKey: _k(f, 'value'), value: f.value, hint: '내용', dense: true,
                        onChanged: (v) => f.value = v),
                  ),
                  IconButton(
                    tooltip: f.isSecret ? '비밀 (숨김)' : '공개',
                    onPressed: () => setState(() => f.isSecret = !f.isSecret),
                    icon: Icon(f.isSecret ? Icons.lock_rounded : Icons.lock_open_rounded,
                        size: 20, color: f.isSecret ? AppColors.primaryPink : AppColors.textMuted),
                  ),
                  IconButton(
                    tooltip: '빼기',
                    onPressed: () => setState(() => d.fields.remove(f)),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => d.fields.add(FieldDraft())),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('항목 추가'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _castEditor() {
    final d = _draft;
    return StudioCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final e in d.cast)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 92,
                    child: EditField(fieldKey: _k(e, 'name'), value: e.name, hint: '이름', dense: true,
                        onChanged: (v) => e.name = v),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: EditField(fieldKey: _k(e, 'role'), value: e.role, hint: '관계 (예: 룸메이트)', dense: true,
                        onChanged: (v) => e.role = v),
                  ),
                  IconButton(
                    tooltip: '빼기',
                    onPressed: () => setState(() => d.cast.remove(e)),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => d.cast.add(CastDraft())),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('인물 추가'),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── 호감도 단계 탭 ─────────────────────────

  Widget _stagesTab() {
    final d = _draft;
    final built = d.buildStages();
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        const StudioSection(
          title: '호감도 단계',
          note: '관계가 깊어지는 단계예요. 이름과 시작 점수(0~100)를 정해요. 첫 단계는 0점부터. '
              '호감도 숫자는 플레이어에게 안 보여요.',
        ),
        for (final s in d.stages)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: EditField(fieldKey: _k(s, 'name'), value: s.name, hint: '단계 이름 (예: 신경 쓰이는 친구)',
                      onChanged: (v) => setState(() {
                            final old = s.name;
                            s.name = v;
                            // 이 단계를 고른 이벤트도 같이 이름을 바꿈
                            for (final e in d.events) {
                              if (e.stage == old) e.stage = v;
                            }
                          })),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 84,
                  child: TextFormField(
                    key: ValueKey(_k(s, 'start')),
                    initialValue: '${s.start}',
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(suffixText: '점~'),
                    onChanged: (v) => setState(() => s.start = (int.tryParse(v) ?? 0).clamp(0, 99)),
                  ),
                ),
                IconButton(
                  tooltip: '단계 빼기',
                  onPressed: d.stages.length > 1 ? () => setState(() => d.stages.remove(s)) : null,
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                ),
              ],
            ),
          ),
        if (d.stages.length < 8)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() {
                final last = d.stages.isEmpty ? 0 : d.stages.map((s) => s.start).reduce((a, b) => a > b ? a : b);
                d.stages.add(StageDraft(start: (last + 20).clamp(0, 95)));
              }),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('단계 추가'),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        if (built.isNotEmpty)
          Text(
            built.map((s) => '${s.stageLabel} ${s.minScore}~${s.maxScore}').join('  →  '),
            style: AppTextStyles.messageTime.copyWith(height: 1.5),
          ),
      ],
    );
  }

  // ───────────────────────── 이벤트 탭 ─────────────────────────

  Widget _eventsTab() {
    final d = _draft;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        const StudioSection(
          title: '이벤트',
          note: '위에서부터 순서대로 진행돼요. 직접 추가하거나, 아래 \'AI로 만들기\'로 한 번에 채울 수 있어요.',
        ),
        for (var i = 0; i < d.events.length; i++) _eventCard(d.events[i], i),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            for (final kind in DraftKind.values)
              if (kind != DraftKind.ending || !d.events.any((e) => e.kind == DraftKind.ending))
                OutlinedButton.icon(
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(kind.label),
                  onPressed: () => setState(() {
                    final event = EventDraft(
                      id: d.newEventId(),
                      kind: kind,
                      stage: d.stageNames.isEmpty ? '' : d.stageNames.last,
                    );
                    // 엔딩은 맨 끝, 나머지는 엔딩 앞에
                    final endingAt = d.events.indexWhere((e) => e.kind == DraftKind.ending);
                    if (kind == DraftKind.ending || endingAt < 0) {
                      d.events.add(event);
                    } else {
                      d.events.insert(endingAt, event);
                    }
                  }),
                ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }

  Widget _eventCard(EventDraft e, int index) {
    final d = _draft;
    final lines = e.scenes.fold(0, (sum, s) => sum + s.lines.where((l) => l.text.trim().isNotEmpty).length);
    return StudioCard(
      highlight: e.kind == DraftKind.special,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: ValueKey(_k(e, 'tile')),
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          title: Text(
            '${index + 1}. ${e.title.trim().isEmpty ? '(제목 없음)' : e.title}',
            style: AppTextStyles.chatBubbleBody.copyWith(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            [
              e.kind.label,
              if (e.kind != DraftKind.ending && e.stage.isNotEmpty) e.stage,
              if (e.kind == DraftKind.special) _windowLabel(e),
              if (e.kind != DraftKind.special && e.notice.isNotEmpty) e.notice,
              if (e.cutscene.isNotEmpty && e.kind != DraftKind.daily) '컷씬',
              '말풍선 $lines개',
            ].join(' · '),
            style: AppTextStyles.messageTime,
          ),
          children: [
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<DraftKind>(
                    initialValue: e.kind,
                    decoration: const InputDecoration(labelText: '종류', isDense: true),
                    items: [for (final k in DraftKind.values) DropdownMenuItem(value: k, child: Text(k.label))],
                    onChanged: (k) => setState(() => e.kind = k ?? e.kind),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (e.kind != DraftKind.ending)
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(_k(e, 'stage-${d.stageNames.join('|')}')),
                      initialValue: d.stageNames.contains(e.stage) ? e.stage : null,
                      decoration: const InputDecoration(labelText: '호감도 단계', isDense: true),
                      items: [for (final s in d.stageNames) DropdownMenuItem(value: s, child: Text(s))],
                      onChanged: (s) => setState(() => e.stage = s ?? ''),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(e.kind.note, style: AppTextStyles.messageTime),
            ),
            EditField(fieldKey: _k(e, 'title'), value: e.title, label: '제목', hint: '예: 두부 실종 사건',
                onChanged: (v) => setState(() => e.title = v)),
            if (e.kind == DraftKind.special)
              _specialTimeEditor(e)
            else ...[
              EditField(
                fieldKey: _k(e, 'notice'),
                value: e.notice,
                label: '장면 전환 문구 (선택)',
                hint: '대화 시작 전에 가운데 떠요. 정확한 시각 대신 다음 날, 그날 밤처럼',
                onChanged: (v) => e.notice = v,
              ),
              Transform.translate(
                offset: const Offset(0, -8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in ['다음 날', '그날 밤', '며칠 뒤', '주말 오후', '다음 날 아침'])
                      StudioPill(
                        label: s,
                        selected: e.notice == s,
                        onTap: () => setState(() {
                          e.notice = s;
                          _version++;
                        }),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            EditField(
              fieldKey: _k(e, 'synopsis'),
              value: e.synopsis,
              label: '줄거리 메모 (제작자용)',
              hint: '무슨 일이 일어나는지. AI로 대사를 쓸 때 참고해요',
              lines: 2,
              onChanged: (v) => e.synopsis = v,
            ),
            if (e.kind != DraftKind.daily)
              EditField(
                fieldKey: _k(e, 'cutscene'),
                value: e.cutscene,
                label: '컷씬 (선택)',
                hint: '앨범에 모이는 장면 설명. 비우면 컷씬 없음. 몇 번째 장면에서 모일지는 대사 탭에서 골라요',
                onChanged: (v) => setState(() => e.cutscene = v),
              ),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.edit_note_rounded, size: 18),
                  label: const Text('대사 편집'),
                  onPressed: () {
                    setState(() => _scriptEvent = e);
                    _tabs.animateTo(3);
                  },
                ),
                TextButton.icon(
                  icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: const Text('AI로 대사 쓰기'),
                  onPressed: _generating ? null : () => _generateOne(e),
                ),
                IconButton(
                  tooltip: '위로',
                  onPressed: index > 0 ? () => setState(() => d.events.insert(index - 1, d.events.removeAt(index))) : null,
                  icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                ),
                IconButton(
                  tooltip: '아래로',
                  onPressed: index < d.events.length - 1
                      ? () => setState(() => d.events.insert(index + 1, d.events.removeAt(index)))
                      : null,
                  icon: const Icon(Icons.arrow_downward_rounded, size: 20),
                ),
                IconButton(
                  tooltip: '이벤트 삭제',
                  onPressed: () async {
                    if (await _confirm('이벤트 삭제', '"${e.title}"와 대사를 지워요.', '삭제')) {
                      setState(() {
                        d.events.remove(e);
                        if (_scriptEvent == e) _scriptEvent = null;
                      });
                    }
                  },
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _hourText(int h) {
    final hh = h % 24;
    final part = hh < 5 ? '새벽' : hh < 12 ? '오전' : hh < 18 ? '오후' : '밤';
    final shown = hh == 0 ? 12 : (hh > 12 ? hh - 12 : hh);
    return '$part $shown시';
  }

  String _windowLabel(EventDraft e) => RealTimeWindow(
        fromHour: e.fromHour,
        toHour: e.toHour,
        date: e.date.trim().isEmpty ? null : e.date.trim(),
      ).label;

  Widget _specialTimeEditor(EventDraft e) {
    DropdownButtonFormField<int> hourPicker(String label, int value, ValueChanged<int> onChanged) =>
        DropdownButtonFormField<int>(
          initialValue: value,
          decoration: InputDecoration(labelText: label, isDense: true),
          items: [for (var h = 0; h < 24; h++) DropdownMenuItem(value: h, child: Text(_hourText(h)))],
          onChanged: (h) => setState(() => onChanged(h ?? value)),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('열리는 실제 시간', style: AppTextStyles.speakerName),
          const Text(
            '플레이어가 이 시간에 대화방에 있을 때 한 번만 와요. 놓쳐도 공략엔 상관없어요.',
            style: AppTextStyles.messageTime,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: hourPicker('부터', e.fromHour, (h) => e.fromHour = h)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: hourPicker('전까지', e.toHour, (h) => e.toHour = h)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          EditField(
            fieldKey: _k(e, 'date'),
            value: e.date,
            hint: '날짜 (선택, 예: 12-25). 비우면 매일 그 시간',
            dense: true,
            onChanged: (v) => setState(() => e.date = v),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── 대사 탭 ─────────────────────────

  Widget _scriptTab() {
    final d = _draft;
    if (d.events.isEmpty) {
      return const Center(child: Text('이벤트 탭에서 대화를 먼저 추가해 주세요', style: AppTextStyles.systemNotice));
    }
    final event = d.events.contains(_scriptEvent) ? _scriptEvent! : d.events.first;
    final hasCutscene = event.cutscene.trim().isNotEmpty && event.kind != DraftKind.daily;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        DropdownButtonFormField<EventDraft>(
          key: ValueKey(_k(event, 'picker-${d.events.length}')),
          initialValue: event,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '편집할 대화', isDense: true),
          items: [
            for (var i = 0; i < d.events.length; i++)
              DropdownMenuItem(
                value: d.events[i],
                child: Text(
                  '${i + 1}. ${d.events[i].title.trim().isEmpty ? '(제목 없음)' : d.events[i].title} · ${d.events[i].kind.label}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (e) => setState(() => _scriptEvent = e),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Expanded(
              child: Text(
                '장면마다 캐릭터 말풍선을 쓰고, 끝에 내가 고를 선택지를 달아요. 선택지가 없는 장면에서 대화가 끝나요. '
                '{{user}}는 플레이어 별명, {{char}}는 캐릭터 이름으로 바뀌어요. 뒤에 붙는 조사도 맞춰 줘요.',
                style: AppTextStyles.messageTime,
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.auto_awesome_outlined, size: 18),
              label: const Text('AI로 쓰기'),
              onPressed: _generating ? null : () => _generateOne(event),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        for (var i = 0; i < event.scenes.length; i++) _sceneCard(event, i, hasCutscene),
        OutlinedButton.icon(
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('장면 추가'),
          onPressed: () => setState(() => event.scenes.add(SceneDraft())),
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }

  Widget _sceneCard(EventDraft event, int index, bool hasCutscene) {
    final scene = event.scenes[index];
    return StudioCard(
      highlight: scene.cutsceneHere && hasCutscene,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('장면 ${index + 1}', style: AppTextStyles.appBarTitle.copyWith(fontSize: 15))),
              if (index == 0) const Text('대화 시작', style: AppTextStyles.messageTime),
              IconButton(
                tooltip: '장면 삭제',
                onPressed: event.scenes.length > 1
                    ? () => setState(() {
                          event.scenes.remove(scene);
                          for (final s in event.scenes) {
                            for (final c in s.choices) {
                              if (c.next == scene) c.next = null;
                            }
                          }
                        })
                    : null,
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
              ),
            ],
          ),
          const Text('캐릭터 말풍선', style: AppTextStyles.speakerName),
          const SizedBox(height: 4),
          for (final line in scene.lines) _lineRow(scene, line),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => scene.lines.add(LineDraft())),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('말풍선 추가'),
            ),
          ),
          if (hasCutscene)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: scene.cutsceneHere,
              title: const Text('이 장면 대사까지 보면 컷씬이 앨범에 모여요', style: AppTextStyles.systemNotice),
              onChanged: (v) => setState(() {
                for (final s in event.scenes) {
                  s.cutsceneHere = false;
                }
                scene.cutsceneHere = v ?? false;
              }),
            ),
          const Divider(),
          Text(scene.choices.isEmpty ? '선택지 없음 · 이 장면에서 대화가 끝나요' : '내 선택지',
              style: AppTextStyles.speakerName),
          const SizedBox(height: 4),
          for (final choice in scene.choices) _choiceCard(event, scene, choice),
          if (scene.choices.length < 4)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => scene.choices.add(ChoiceDraft())),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('선택지 추가'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _lineRow(SceneDraft scene, LineDraft line) {
    final speeds = <double, String>{0.6: '툭 빠르게', 1.0: '보통', 1.5: '망설이며'};
    final speedKey = speeds.keys.reduce((a, b) => (a - line.speed).abs() <= (b - line.speed).abs() ? a : b);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: EditField(fieldKey: _k(line, 'text'), value: line.text, hint: '캐릭터가 보내는 톡', dense: true,
                    onChanged: (v) => line.text = v),
              ),
              PopupMenuButton<double>(
                tooltip: '치는 빠르기',
                initialValue: speedKey,
                onSelected: (v) => setState(() => line.speed = v),
                itemBuilder: (_) => [
                  for (final entry in speeds.entries) PopupMenuItem(value: entry.key, child: Text(entry.value)),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(speeds[speedKey]!, style: AppTextStyles.messageTime.copyWith(color: AppColors.aiActivePurple)),
                ),
              ),
              IconButton(
                tooltip: line.photo.isEmpty ? '사진 말풍선으로' : '사진 빼기',
                onPressed: () => setState(() {
                  line.photo = line.photo.isEmpty ? '사진' : '';
                  _version++;
                }),
                icon: Icon(Icons.image_outlined, size: 20,
                    color: line.photo.isEmpty ? AppColors.textMuted : AppColors.primaryPink),
              ),
              IconButton(
                tooltip: '말풍선 빼기',
                onPressed: scene.lines.length > 1 ? () => setState(() => scene.lines.remove(line)) : null,
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
            ],
          ),
          if (line.photo.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 96),
              child: EditField(fieldKey: _k(line, 'photo'), value: line.photo, hint: '보내는 사진 설명', dense: true,
                  onChanged: (v) => line.photo = v),
            ),
        ],
      ),
    );
  }

  Widget _choiceCard(EventDraft event, SceneDraft scene, ChoiceDraft choice) {
    final others = [for (final s in event.scenes) if (s != scene) s];
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.myBubble.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: EditField(fieldKey: _k(choice, 'label'), value: choice.label, hint: '버튼 문구 (예: 같이 가자고 하기)',
                    dense: true, onChanged: (v) => choice.label = v),
              ),
              IconButton(
                tooltip: '선택지 빼기',
                onPressed: () => setState(() => scene.choices.remove(choice)),
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 6),
          EditField(
            fieldKey: _k(choice, 'messages'),
            value: choice.messages,
            hint: '누르면 내가 보내는 톡 (줄마다 말풍선 하나)',
            lines: 2,
            dense: true,
            onChanged: (v) => choice.messages = v,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: choice.affection,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '호감도', isDense: true),
                  items: [
                    for (final v in {-3, -1, 0, 1, 2, 3, 4, 5, 6, 8, choice.affection}.toList()..sort())
                      DropdownMenuItem(value: v, child: Text(v > 0 ? '+$v' : '$v')),
                  ],
                  onChanged: (v) => setState(() => choice.affection = v ?? choice.affection),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<SceneDraft?>(
                  key: ValueKey(_k(choice, 'next-${event.scenes.length}')),
                  initialValue: others.contains(choice.next) ? choice.next : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '다음', isDense: true),
                  items: [
                    const DropdownMenuItem<SceneDraft?>(value: null, child: Text('대화 끝')),
                    for (final s in others)
                      DropdownMenuItem<SceneDraft?>(value: s, child: Text('장면 ${event.scenes.indexOf(s) + 1}로')),
                  ],
                  onChanged: (s) => setState(() => choice.next = s),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
