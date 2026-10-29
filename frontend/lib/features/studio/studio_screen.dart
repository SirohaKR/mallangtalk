import 'dart:async';
import 'dart:convert';
import 'dart:math';
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
import '../../shared/widgets/mallang_loading.dart';
import '../../core/network/ai_provider.dart';
import '../chat/chat_ai_sheet.dart';
import '../chat/chat_notifier.dart';
import '../chat/chat_theme.dart';
import '../chat/service_messages.dart';
import '../library/character_library.dart';
import '../settings/byok_settings.dart';
import '../settings/user_profile.dart';
import 'character_import.dart';
import 'photo_box.dart';
import 'scenario_draft.dart';
import 'studio_widgets.dart';

/// [초보자 노트] 캐릭터 만들기(편집기) 화면입니다. 한 화면에 한 단계씩, 8단계로 만듭니다.
/// 기본 → 대표색 → 프로필 → 성격·말투 → 이야기 → 인물·비밀 → 호감도·대본 → 마무리
/// - 3~6단계의 '빈 칸 AI로 채우기'는 그 단계의 빈 칸만 AI가 써 넣어요.
/// - 7단계 맨 위 'AI로 생성하기'를 누르면 앞 단계 설정을 토대로 이벤트·일상 대화·특별 이벤트·엔딩과 모든 대사를 채워 줍니다.
/// - 직접 만들 때는 7단계에서 대화를 추가하고, 대사 편집에서 장면·말풍선·선택지를 하나씩 넣습니다.
/// - 대화 옆 ✨로 그 대화만 AI로 다시 써도 돼요.
/// initial을 주면 이미 만든 캐릭터를 고치는 화면이 됩니다.
/// 내 캐릭터를 고치는 화면 (/edit/캐릭터ID)
class EditCharacterPage extends ConsumerWidget {
  const EditCharacterPage({super.key, required this.characterId});

  final String characterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(characterLibraryProvider.select((list) => list.where((e) => e.id == characterId).firstOrNull));
    if (entry == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('캐릭터를 찾을 수 없어요')));
    }
    final galleryItem = ref.watch(galleryProvider).valueOrNull?.where((g) => g.character.id == characterId).firstOrNull;
    final isCreator = entry.source == CharacterSource.created && (galleryItem == null || galleryItem.mine);
    if (!isCreator) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('내가 만든 캐릭터만 고칠 수 있어요', style: AppTextStyles.systemNotice)),
      );
    }
    return StudioScreen(initial: entry.bundle);
  }
}

class StudioScreen extends ConsumerStatefulWidget {
  const StudioScreen({super.key, this.initial});

  final ScenarioBundle? initial;

  @override
  ConsumerState<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends ConsumerState<StudioScreen>
    with AutomaticKeepAliveClientMixin {
  late ScenarioDraft _draft;
  /// 초안을 통째로 바꿀 때마다 올려서 입력칸을 새로 채움
  int _version = 0;
  EventDraft? _scriptEvent;

  bool _generating = false;
  String _progressText = '';
  /// 0~1. 단계를 셀 수 없는 일(이벤트 하나 쓰기)은 null이라 퍼센트를 숨김
  double? _progress;
  int _eventsPerStage = 2;
  int _dailiesPerStage = 3;
  int _specials = 1;

  bool get _editing => widget.initial != null;

  @override
  bool get wantKeepAlive => true; // 탭을 옮겨도 쓰던 내용 유지 (만들던 초안은 자동 저장돼서 다시 열면 이어 써요)

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
        _step = 0;
        _jumpKeys.clear();
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
      _toast('기본 단계에서 이름을 먼저 적어 주세요');
      _goStep(0);
      return false;
    }
    if (_draft.setting.trim().length < 10) {
      _toast('이야기 단계의 캐릭터 설정(성격·말투·취미)을 조금 더 자세히 적어 주세요');
      _storyPart = 0;
      _goStep(4);
      return false;
    }
    final stageProblems = _draft.problems().where((p) => p.startsWith('[호감도 단계]')).toList();
    if (stageProblems.isNotEmpty) {
      _toast(stageProblems.first);
      _goStep(6);
      return false;
    }
    if (!ref.read(byokSettingsProvider).canUseAi) {
      _toast('설정에서 AI 키를 먼저 넣어 주세요');
      return false;
    }
    return true;
  }

  /// 대사가 하나도 없는 대화 (제목이 있어야 AI가 씀)
  List<EventDraft> get _blankEvents => [
        for (final e in _draft.events)
          if (e.title.trim().isNotEmpty && !e.scenes.any((s) => s.lines.any((l) => l.text.trim().isNotEmpty))) e,
      ];

  /// 예상 호출 수 → '호출 N번, 약 N분 · 약 N원'. 호출 한 번에 입력 약 4천·출력 약 1천2백 토큰으로 어림
  String _estimate(int calls) {
    final byok = ref.read(byokSettingsProvider);
    final minutes = (calls * 35 / 60).ceil();
    final m = byok.modelOption;
    var text = '예상 · 호출 $calls번, 약 $minutes분';
    if (m != null) {
      final won = calls * (4000 * m.inputUsdPerMTok + 1200 * m.outputUsdPerMTok) / 1e6 * 1400;
      text += ' · 약 ${won < 10 ? '10원 안쪽' : '${(won / 10).round() * 10}원'}';
      if (byok.provider == AiProvider.gemini && m.note.contains('무료')) text += ' (무료 한도 안이면 0원)';
    }
    return text;
  }

  Future<void> _openAiSheet() async {
    if (!_readyForAi()) return;
    final blank = _blankEvents;
    var mode = blank.isNotEmpty ? 'blank' : 'all';
    final picked = <EventDraft>{if (_scriptEvent != null && _draft.events.contains(_scriptEvent)) _scriptEvent!};
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.surfaceWhite,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          void update(VoidCallback f) {
            setState(f);
            setSheet(() {});
          }

          final total = _draft.stageNames.length * (_eventsPerStage + _dailiesPerStage) + _specials + 1;
          final titled = [for (final e in _draft.events) if (e.title.trim().isNotEmpty) e];
          final calls = switch (mode) {
            'blank' => blank.length,
            'pick' => picked.length,
            _ => total + 1,
          };
          Widget option(String value, String title, String note, {bool enabled = true}) => RadioListTile<String>(
                key: ValueKey('ai_mode_$value'),
                value: value,
                enabled: enabled,
                contentPadding: EdgeInsets.zero,
                activeColor: const Color(0xFFB83B66),
                title: Text(title, style: AppTextStyles.choiceButton),
                subtitle: Text(note, style: AppTextStyles.messageTime),
              );
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('AI로 생성하기', style: AppTextStyles.appBarTitle),
                    const SizedBox(height: 4),
                    const Text('무엇을 만들까요', style: AppTextStyles.speakerName),
                    RadioGroup<String>(
                      groupValue: mode,
                      onChanged: (v) => setSheet(() => mode = v ?? mode),
                      child: Column(
                        children: [
                          option(
                            'blank',
                            '비어 있는 대화만',
                            blank.isEmpty ? '대사가 빈 대화가 없어요' : '내가 쓴 대사는 그대로 두고 빈 대화 ${blank.length}개만 써요',
                            enabled: blank.isNotEmpty,
                          ),
                          option('all', '전부 새로', '호감도 단계부터 대본을 처음부터 다시 짜요. 지금 있는 대화는 바뀌어요'),
                          option(
                            'pick',
                            '골라서',
                            picked.isEmpty
                                ? '대화를 골라 그것만 써요'
                                : '대화를 골라 그것만 써요 (지금 ${picked.length}개${picked.length == 1 ? ': ${picked.single.title}' : ''})',
                            enabled: titled.isNotEmpty,
                          ),
                        ],
                      ),
                    ),
                    if (mode == 'all') ...[
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
                      Text('대화 $total개 · 비어 있는 캐릭터 정보(한줄 소개·태그·세계관·프로필 항목)도 채워 줘요',
                          style: AppTextStyles.messageTime),
                    ],
                    if (mode == 'pick')
                      for (final e in titled)
                        CheckboxListTile(
                          key: ValueKey('ai_pick_${_draft.events.indexOf(e)}'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: picked.contains(e),
                          activeColor: const Color(0xFFB83B66),
                          title: Text('${_draft.events.indexOf(e) + 1}. ${e.title} · ${e.kind.label}',
                              overflow: TextOverflow.ellipsis),
                          onChanged: (v) => setSheet(() => v == true ? picked.add(e) : picked.remove(e)),
                        ),
                    const Divider(height: AppSpacing.lg),
                    Row(
                      children: [
                        const Text('사용할 AI', style: AppTextStyles.speakerName),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(aiModelName(ref.read(byokSettingsProvider)),
                              style: AppTextStyles.choiceButton, overflow: TextOverflow.ellipsis),
                        ),
                        TextButton(
                          key: const ValueKey('ai_change_model'),
                          onPressed: () async {
                            await showChatAiSheet(sheetContext, accent: const Color(0xFFB83B66));
                            setSheet(() {});
                          },
                          child: const Text('바꾸기'),
                        ),
                      ],
                    ),
                    Text(_estimate(calls), key: const ValueKey('ai_estimate'), style: AppTextStyles.messageTime),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton.icon(
                      key: const ValueKey('ai_start'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFB83B66),
                        minimumSize: const Size.fromHeight(48),
                      ),
                      icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                      label: const Text('생성 시작'),
                      onPressed: calls == 0 ? null : () => Navigator.pop(sheetContext, true),
                    ),
                    const SizedBox(height: 6),
                    const Text('내 AI 키로 써요. 다 만든 뒤에도 대사는 하나하나 고칠 수 있어요.',
                        textAlign: TextAlign.center, style: AppTextStyles.messageTime),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    if (go != true || !mounted) return;
    switch (mode) {
      case 'blank':
        await _writeMany(blank);
      case 'pick':
        await _writeMany([for (final e in _draft.events) if (picked.contains(e)) e]);
      default:
        await _generateAll();
    }
  }

  /// 고른 대화들의 대사를 차례로 AI로 씀 (중간에 멈추면 앞에서 쓴 건 남김)
  Future<void> _writeMany(List<EventDraft> targets) async {
    if (targets.isEmpty) return;
    setState(() {
      _generating = true;
      _progress = 0;
      _progressText = '대사를 쓰는 중';
    });
    var done = 0;
    try {
      for (final event in targets) {
        if (!mounted) return;
        setState(() {
          _progressText = '"${event.title}" 대사를 쓰는 중 (${done + 1}/${targets.length})';
          _progress = done / targets.length;
        });
        await _writeScriptInto(event);
        done++;
      }
      if (!mounted) return;
      setState(() {
        _scriptEvent = targets.length == 1 ? targets.single : null;
        _step = 6;
      });
      _toast('대화 $done개의 대사를 썼어요. 고칠 곳을 고친 뒤 저장해 주세요');
    } on ClaudeChatException catch (e) {
      if (mounted) _toast(done > 0 ? '${e.message} (앞의 대화 $done개는 써 뒀어요)' : e.message);
    } catch (e) {
      if (mounted) _toast('대사를 쓰는 중 문제가 생겼어요: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  /// 대화 하나의 대사를 AI로 써서 그 대화에 넣음 (제목·줄거리 메모와 다른 대화 목차를 보고)
  Future<void> _writeScriptInto(EventDraft event) async {
    final byok = ref.read(byokSettingsProvider);
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
    });
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
      // 올려 둔 사진함은 그대로 (새 대본의 사진 말풍선은 설명이 같으면 저절로 붙음)
      final old = _draft;
      final next = ScenarioDraft.fromBundle(bundle);
      for (final p in old.photos) {
        next.addPhoto(p);
      }
      next.photoTriggers.addAll(old.photoTriggers);
      _replaceDraft(next);
      _goStep(6);
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
    setState(() {
      _generating = true;
      _progress = null;
      _progressText = '"${event.title}" 대사를 쓰는 중';
    });
    try {
      await _writeScriptInto(event);
      if (!mounted) return;
      setState(() {
        _scriptEvent = event;
        _step = 6;
      });
    } on ClaudeChatException catch (e) {
      if (mounted) _toast(e.message);
    } catch (e) {
      if (mounted) _toast('대사를 쓰는 중 문제가 생겼어요: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  // ───────────────────────── 사진 자리 ─────────────────────────

  /// 수정하러 가기에서 스크롤해 갈 곳 (사진 말풍선, 이벤트 컷씬)
  final _jumpKeys = <Object, GlobalKey>{};
  GlobalKey _jumpKey(Object owner) => _jumpKeys.putIfAbsent(owner, GlobalKey.new);

  PhotoState _photoState(PhotoSlot slot) {
    if (slot.filled) return PhotoState.filled;
    if (_draft.sharedPhotoFor(slot) != null) return PhotoState.shared;
    return _draft.unusedPhotos.isEmpty ? PhotoState.card : PhotoState.missing;
  }

  static String _photoStateText(PhotoState state) => switch (state) {
        PhotoState.filled => '사진 골랐어요',
        PhotoState.shared => '설명이 같은 사진이 나와요',
        PhotoState.missing => '사진함에 사진이 있는데 아직 안 골랐어요',
        PhotoState.card => '사진이 없어서 설명 카드로 보여요',
      };

  /// 이벤트에 사진이 어디 있는지 보여 주는 꼬리표 (이벤트 카드·대사 탭)
  List<Widget> _photoTags(EventDraft e) {
    final slots = e.photoSlots;
    final cut = slots.where((s) => s.isCutscene).firstOrNull;
    final lines = [for (final s in slots) if (!s.isCutscene) _photoState(s)];
    final ready = lines.where((s) => s == PhotoState.filled || s == PhotoState.shared).length;
    return [
      if (cut != null)
        switch (_photoState(cut)) {
          PhotoState.filled => const PhotoTag(label: '컷씬 사진 있음', state: PhotoState.filled),
          PhotoState.shared => const PhotoTag(label: '컷씬 사진 (같은 설명)', state: PhotoState.shared),
          PhotoState.missing => const PhotoTag(label: '컷씬 사진 안 고름', state: PhotoState.missing),
          PhotoState.card => const PhotoTag(label: '컷씬 설명 카드', state: PhotoState.card),
        },
      if (lines.isNotEmpty)
        PhotoTag(
          label: '사진 말풍선 $ready/${lines.length}',
          state: ready == lines.length
              ? PhotoState.filled
              : lines.contains(PhotoState.missing)
                  ? PhotoState.missing
                  : PhotoState.card,
        ),
    ];
  }

  /// 대사 탭에서 그 이벤트를 열고 사진 자리까지 스크롤
  void _jumpTo(PhotoSlot slot) {
    setState(() {
      _scriptEvent = slot.event;
      _step = 6;
    });
    // 대사 편집이 그려진 다음 프레임에 그 자리로 스크롤
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _jumpKey(slot.line ?? slot.event).currentContext;
      if (target != null && target.mounted) {
        Scrollable.ensureVisible(target, alignment: 0.15, duration: const Duration(milliseconds: 300));
      }
    });
  }

  /// 사진을 안 고른 자리 목록. 고른 자리(수정하러 가기), true(그냥 저장), null(닫기)
  Future<Object?> _askMissingPhotos(List<PhotoSlot> missing, int linked) {
    final byEvent = <EventDraft, List<PhotoSlot>>{};
    for (final s in missing) {
      byEvent.putIfAbsent(s.event, () => []).add(s);
    }
    return showDialog<Object?>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('사진을 안 고른 곳이 있어요'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${linked > 0 ? '설명이 같은 사진 등 $linked곳은 자동으로 연결했어요. ' : ''}'
                '사진함에 안 쓴 사진이 있는데 아래는 사진을 안 골라서, 그대로 저장하면 설명 카드로 보여요.',
                style: AppTextStyles.systemNotice,
              ),
              for (final entry in byEvent.entries) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  '${_draft.events.indexOf(entry.key) + 1}. ${entry.key.title.trim().isEmpty ? '(제목 없음)' : entry.key.title}',
                  style: AppTextStyles.speakerName,
                ),
                for (final slot in entry.value)
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.affectionWarm),
                      const SizedBox(width: 4),
                      Expanded(child: Text(slot.where, style: AppTextStyles.messageTime)),
                      TextButton(onPressed: () => Navigator.pop(c, slot), child: const Text('수정하러 가기')),
                    ],
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('닫기')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('그냥 저장')),
        ],
      ),
    );
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
    // 사진함 사진을 컷씬·사진 말풍선에 붙일 수 있는 건 붙이고, 못 붙인 곳은 저장 전에 알려 줌
    final linked = _draft.autoLinkPhotos();
    if (linked > 0) setState(() {});
    final missing = _draft.missingPhotos();
    if (missing.isNotEmpty) {
      final answer = await _askMissingPhotos(missing, linked);
      if (!mounted) return;
      if (answer is PhotoSlot) {
        _jumpTo(answer);
        return;
      }
      if (answer != true) return;
    } else if (linked > 0) {
      _toast('사진을 안 고른 $linked곳에 사진함 사진을 자동으로 연결했어요');
    }
    var bundle = _draft.toBundle();
    if (!_draft.isService && !bestPathClears(bundle)) {
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
    ref.invalidate(chatRoomProvider(freeRoomId(bundle.character.id)));
    if (!mounted) return;
    if (_editing) {
      Navigator.of(context).pop();
      _toast('${bundle.character.name} 수정 내용을 저장했어요');
    } else {
      _toast('${bundle.character.name}을(를) 저장했어요. 내 말랑이 > 내가 만든에서 볼 수 있어요');
      _replaceDraft(ScenarioDraft.blank());
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    }
  }

  // ───────────────────────── 화면 ─────────────────────────

  /// 만들기 단계 (한 화면에 한 단계, 위 막대를 누르면 바로 이동).
  /// 이야기 말랑이는 8단계, 서비스 말랑이는 기본·대표색·보내기·마무리 4단계
  List<int> get _stepIds => _draft.isService ? const [0, 1, 8, 7] : const [0, 1, 2, 3, 4, 5, 6, 7];

  static const _stepNames = [
    ('기본', '말랑이 찾기 카드와 채팅방에 보이는 것들'),
    ('대표색', ''),
    ('프로필', ''),
    ('성격·말투', ''),
    ('이야기', ''),
    ('인물·비밀', ''),
    ('호감도·대본', ''),
    ('마무리', ''),
    ('보내기', ''),
  ];

  List<(String, String)> get _steps => [for (final id in _stepIds) _stepNames[id]];

  /// 이 단계에서 '빈 칸 AI로 채우기'로 채울 칸 (없으면 버튼 없음)
  static const _fillFields = <int, List<String>>{
    2: ['profile_fields'],
    3: ['quote', 'sample_quotes', 'traits'],
    4: ['world_setting', 'user_role'],
    5: ['extra_cast', 'secret'],
  };

  int _step = 0;

  /// 이야기 단계에서 쓰는 글 (0 캐릭터 설정, 1 세계관, 2 나는)
  int _storyPart = 0;

  void _goStep(int step) {
    FocusScope.of(context).unfocus();
    setState(() => _step = step.clamp(0, _steps.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final (title, _) = _steps[_step];
    final last = _steps.length - 1;
    final fill = _fillFields[_stepIds[_step]];
    final body = Center(
      child: ConstrainedBox(
        constraints: AppSpacing.pageConstraints(context, maxDesktop: 760),
        child: Column(
          children: [
            // 단계 이름 + 빈 칸 채우기 + 몇 번째 단계 + 8칸 막대
            Container(
              color: AppColors.surfaceWhite,
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 4, AppSpacing.lg, 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(title, style: AppTextStyles.appBarTitle.copyWith(fontSize: 18))),
                      if (fill != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: ActionChip(
                            key: const ValueKey('studio_fill'),
                            avatar: const Icon(Icons.auto_awesome_rounded, size: 15, color: Color(0xFF8E2E52)),
                            label: const Text('빈 칸 AI로 채우기'),
                            labelStyle: AppTextStyles.messageTime
                                .copyWith(color: const Color(0xFF8E2E52), fontWeight: FontWeight.w700),
                            backgroundColor: const Color(0xFFF6E3EA),
                            side: BorderSide.none,
                            shape: const StadiumBorder(),
                            visualDensity: VisualDensity.compact,
                            onPressed: _generating ? null : () => _fillBlanks(fill),
                          ),
                        ),
                      Text('${_step + 1} / ${_steps.length}', style: AppTextStyles.messageTime),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (var i = 0; i < _steps.length; i++)
                        Expanded(
                          child: GestureDetector(
                            key: ValueKey('studio_step_$i'),
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _goStep(i),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Container(
                                height: 6,
                                margin: const EdgeInsets.symmetric(horizontal: 2),
                                decoration: BoxDecoration(
                                  color: i == _step
                                      ? const Color(0xFFB83B66)
                                      : i < _step
                                          ? const Color(0xFFE7A9BE)
                                          : AppColors.borderLight,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _stepBody(_stepIds[_step])),
            Container(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 10, AppSpacing.lg, 14),
              decoration: const BoxDecoration(
                color: AppColors.surfaceWhite,
                border: Border(top: BorderSide(color: AppColors.borderLight)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 96,
                    child: OutlinedButton(
                      key: const ValueKey('studio_prev'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                      onPressed: _step == 0 ? null : () => _goStep(_step - 1),
                      child: const Text('이전'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('studio_next'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFB83B66),
                        minimumSize: const Size.fromHeight(50),
                        textStyle: AppTextStyles.choiceButton,
                      ),
                      onPressed: _generating ? null : (_step == last ? _save : () => _goStep(_step + 1)),
                      child: Text(
                        _step == last ? (_editing ? '수정 저장' : '저장하기') : '다음: ${_steps[_step + 1].$1}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    // AI가 만드는 동안 화면을 회색으로 덮고 말랑이가 통통 튀며 진행 상황을 알려 줌
    final screen = Stack(
      children: [
        body,
        if (_generating)
          Positioned.fill(child: MallangLoadingOverlay(message: _progressText, progress: _progress)),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? '${widget.initial!.character.name} 고치기' : '새 말랑이 만들기'),
        actions: [
          TextButton(
            onPressed: _generating ? null : _save,
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF8E2E52)),
            child: const Text('저장'),
          ),
          PopupMenuButton<String>(
            tooltip: '더 보기',
            onSelected: _onMenu,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'new', child: Text('새로 만들기')),
              PopupMenuItem(value: 'import', child: Text('캐릭터 파일(.json) 불러오기')),
              PopupMenuItem(value: 'export', child: Text('캐릭터 파일로 내보내기')),
            ],
          ),
        ],
      ),
      body: screen,
    );
  }

  Widget _stepBody(int step) {
    final d = _draft;
    const pad = EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md);
    switch (step) {
      case 0:
        final preview = d.buildCharacter();
        return ListView(
          padding: pad,
          children: [
            const Text('어떤 말랑이인가요', style: AppTextStyles.speakerName),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              key: const ValueKey('studio_kind'),
              segments: const [
                ButtonSegment(value: '', label: Text('이야기 말랑이')),
                ButtonSegment(value: CharacterModel.serviceKind, label: Text('서비스 말랑이')),
              ],
              selected: {d.kind},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() {
                d.kind = v.first;
                _step = 0;
              }),
            ),
            const SizedBox(height: 4),
            Text(
              d.isService
                  ? '정해진 때마다 먼저 톡을 보내 주는 말랑이 (운세·행운의 편지·아침 응원 같은). 호감도·엔딩 없이 처음부터 친한 사이예요.'
                  : '호감도 단계·이벤트·엔딩이 있는 말랑이. 스토리와 자유대화 둘 다 돼요.',
              style: AppTextStyles.messageTime,
            ),
            const SizedBox(height: AppSpacing.md),
            // 프로필 사진(동그라미)과 대표 사진(찾기 카드·상세 커버)을 따로 올림
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    InkWell(
                      key: const ValueKey('studio_avatar'),
                      customBorder: const CircleBorder(),
                      onTap: () async {
                        final image = await pickProfileImage(context);
                        if (image != null) setState(() => d.avatarUrl = image);
                      },
                      child: CharacterAvatar(character: preview, radius: 42),
                    ),
                    const SizedBox(height: 6),
                    Text(d.avatarUrl.isEmpty ? '프로필 고르기' : '프로필', style: AppTextStyles.messageTime),
                  ],
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        key: const ValueKey('studio_cover'),
                        borderRadius: BorderRadius.circular(12),
                        onTap: () async {
                          final image = await pickPhoto(context);
                          if (image != null) setState(() => d.coverUrl = image);
                        },
                        child: Container(
                          height: 112,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: d.coverUrl.isEmpty ? Border.all(color: AppColors.borderLight) : null,
                            color: AppColors.surfaceWhite,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: d.coverUrl.isEmpty
                              ? const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add_photo_alternate_outlined, color: AppColors.textSecondary),
                                    SizedBox(height: 4),
                                    Text('대표 사진 올리기', style: AppTextStyles.messageTime),
                                  ],
                                )
                              : CharacterImage(character: preview, cover: true),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Expanded(
                            child: Text('대표 사진 · 말랑이 찾기 카드와 상세 커버. 비우면 프로필 사진을 써요',
                                style: AppTextStyles.messageTime),
                          ),
                          if (d.coverUrl.isNotEmpty)
                            TextButton(
                              onPressed: () => setState(() => d.coverUrl = ''),
                              child: const Text('빼기'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            EditField(fieldKey: _k(d, 'name'), value: d.name, label: '이름', hint: '예: 윤도하', maxLength: 20,
                onChanged: (v) => setState(() => d.name = v)),
            EditField(fieldKey: _k(d, 'status'), value: d.statusMessage, label: '상태 메시지',
                hint: '채팅방 이름 아래 보여요', onChanged: (v) => d.statusMessage = v),
            EditField(fieldKey: _k(d, 'tagline'), value: d.tagline, label: '한줄 소개',
                hint: '말랑이 찾기 카드에 보여요. 비우면 AI가 지어 줘요', lines: 2, onChanged: (v) => d.tagline = v),
            EditField(fieldKey: _k(d, 'tags'), value: d.tags, label: '태그',
                hint: '쉼표로 구분. 예: 남사친, 장난꾸러기, 고양이집사', onChanged: (v) => d.tags = v),
            const Text('위의 막대를 누르면 원하는 단계로 바로 갈 수 있어요. 다 채우지 않아도 다음으로 넘어가요.',
                style: AppTextStyles.messageTime),
          ],
        );
      case 1:
        return ListView(padding: pad, children: [_colorStep()]);
      case 8:
        return _serviceStep(pad);
      case 2:
        return ListView(
          padding: pad,
          children: [
            const Text('성별', style: AppTextStyles.speakerName),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              key: const ValueKey('studio_gender'),
              segments: const [
                ButtonSegment(value: 'male', label: Text('남성')),
                ButtonSegment(value: 'female', label: Text('여성')),
                ButtonSegment(value: 'none', label: Text('미정')),
              ],
              selected: {if (d.gender.isNotEmpty) d.gender},
              emptySelectionAllowed: true,
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() => d.gender = v.isEmpty ? '' : v.first),
            ),
            const SizedBox(height: 4),
            const Text('AI 대본·자유대화에 쓰여요. 미정이면 AI가 성별을 드러내지 않게 써요.', style: AppTextStyles.messageTime),
            const SizedBox(height: AppSpacing.md),
            const Text('프로필 항목', style: AppTextStyles.speakerName),
            const Text('나이, 신분, 외모, 좋아하는 것처럼 짧은 항목. 자물쇠 = 플레이어에게 안 보임', style: AppTextStyles.messageTime),
            const SizedBox(height: 6),
            _fieldsEditor(),
          ],
        );
      case 3:
        return ListView(
          padding: pad,
          children: [
            StudioCard(child: _traitsEditor()),
            const SizedBox(height: AppSpacing.md),
            EditField(fieldKey: _k(d, 'quote'), value: d.quote, label: '대표 대사 · 상세 화면 맨 위에 보여요',
                hint: '이 캐릭터다운 한 마디', lines: 2, onChanged: (v) => d.quote = v),
            const Text('대사 예시 · AI가 말투를 배워요', style: AppTextStyles.speakerName),
            const SizedBox(height: 6),
            for (var i = 0; i < d.sampleQuotes.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 92,
                      child: EditField(
                          fieldKey: _k(d, 'sq-s-$i-${d.sampleQuotes.length}'),
                          value: d.sampleQuotes[i].situation,
                          hint: '상황',
                          dense: true,
                          onChanged: (v) => d.sampleQuotes[i] = CharacterQuote(situation: v, body: d.sampleQuotes[i].body)),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: EditField(
                          fieldKey: _k(d, 'sq-b-$i-${d.sampleQuotes.length}'),
                          value: d.sampleQuotes[i].body,
                          hint: '대사',
                          dense: true,
                          onChanged: (v) => d.sampleQuotes[i] = CharacterQuote(situation: d.sampleQuotes[i].situation, body: v)),
                    ),
                    IconButton(
                      tooltip: '빼기',
                      onPressed: () => setState(() => d.sampleQuotes.removeAt(i)),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => d.sampleQuotes.add(const CharacterQuote(situation: '', body: ''))),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('예시 추가'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text('타자 스타일', style: AppTextStyles.speakerName),
            const SizedBox(height: 6),
            TypingStylePicker(value: d.typing, onChanged: (v) => setState(() => d.typing = v)),
          ],
        );
      case 4:
        const parts = ['캐릭터 설정', '세계관', '나는'];
        const notes = [
          '성격, 말투 습관(ㅋㅋ를 자주 씀 등), 취미, 관심사, 나와의 사이. 자세할수록 AI가 잘 따라 해요. 상세 화면에 그대로 보여요',
          '이야기의 배경이 되는 곳·시대·분위기. 비우면 AI가 채워 줘요',
          '플레이어가 누구인지. {{user}}는 플레이어 별명, {{char}}는 캐릭터 이름으로 바뀌어요',
        ];
        return Padding(
          padding: pad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<int>(
                key: const ValueKey('studio_story_parts'),
                segments: [for (var i = 0; i < parts.length; i++) ButtonSegment(value: i, label: Text(parts[i]))],
                selected: {_storyPart},
                showSelectedIcon: false,
                onSelectionChanged: (v) => setState(() => _storyPart = v.first),
              ),
              const SizedBox(height: 8),
              Text(notes[_storyPart], style: AppTextStyles.messageTime),
              const SizedBox(height: 8),
              Expanded(
                child: switch (_storyPart) {
                  0 => BigTextField(
                      fieldKey: _k(d, 'setting'),
                      value: d.setting,
                      hint: '예) 1년 전 교양 수업 팀플에서 만나 거의 매일 연락하는 남사친. 장난기 많고 ㅋㅋ를 달고 산다. '
                          '진지해지면 말이 짧아지고 띄어쓰기가 정확해진다. 주말 새벽엔 한강을 뛰고…',
                      onChanged: (v) => d.setting = v,
                    ),
                  1 => BigTextField(
                      fieldKey: _k(d, 'world'),
                      value: d.world,
                      hint: '예) 지금의 서울. 홍대 근처 대학가에서 자취하는 대학생들의 평범한 봄~여름…',
                      onChanged: (v) => d.world = v,
                    ),
                  _ => BigTextField(
                      fieldKey: _k(d, 'role'),
                      value: d.userRole,
                      hint: '예) {{user}} · 1년 전 교양 수업 팀플에서 {{char}}와 만난 친구. 거의 매일 연락하는 사이',
                      onChanged: (v) => d.userRole = v,
                    ),
                },
              ),
            ],
          ),
        );
      case 5:
        return ListView(
          padding: pad,
          children: [
            const Text('주변 인물', style: AppTextStyles.speakerName),
            const Text('대화에 이름이 나오는 친구·가족·반려동물. 상세 화면에 보여요', style: AppTextStyles.messageTime),
            const SizedBox(height: 6),
            _castEditor(),
            EditField(
              fieldKey: _k(d, 'secret'),
              value: d.secret,
              label: '비밀',
              hint: '예) 사실 처음 만난 날부터 좋아했다. 친구 사이가 깨질까 봐 장난으로 넘겨 왔다…',
              lines: 5,
              onChanged: (v) => d.secret = v,
            ),
            const Text('플레이어에게 안 보이고, AI 대본과 자유대화가 서서히 드러내요', style: AppTextStyles.messageTime),
          ],
        );
      case 6:
        return _scriptEvent != null && d.events.contains(_scriptEvent) ? _scriptTab() : _storyboardStep();
      default:
        return _finishStep();
    }
  }

  /// 2단계: 대표색 고르기 + 톡방 꾸미기 + 미리보기
  Widget _colorStep() {
    final d = _draft;
    const presets = [
      '#E86A92', '#B83B66', '#E8845C', '#D9A23A', '#5BA370', '#3E9C9C', '#6B8FD6', '#3B4A8C', '#7C5CBF', '#5E4E54',
    ];
    final preview = d.buildCharacter();
    final theme = ChatTheme.of(preview.themeColor.isEmpty ? preview.copyWith(themeColor: '#E86A92') : preview);
    final current = d.themeColor.toUpperCase();
    Widget option(String label, bool on, VoidCallback onTap, {Key? key}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: OutlinedButton(
              key: key,
              style: OutlinedButton.styleFrom(
                backgroundColor: on ? Color.lerp(AppColors.surfaceWhite, theme.accent, 0.1) : null,
                side: BorderSide(color: on ? theme.accent : AppColors.borderLight, width: on ? 2 : 1),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onPressed: () => setState(onTap),
              child: Text(label, style: AppTextStyles.messageTime.copyWith(color: AppColors.textPrimary)),
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '대표색은 이 말랑이를 나타내는 색이에요. 톡방 꾸미기, 프로필의 호감도 말랑이, 앨범·사진 보기에 쓰여요.',
          style: AppTextStyles.systemNotice,
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final hex in presets)
              GestureDetector(
                key: ValueKey('studio_color_$hex'),
                onTap: () => setState(() {
                  d.themeColor = hex;
                  _version++;
                }),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Color(int.parse('FF${hex.substring(1)}', radix: 16)),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: current == hex ? AppColors.textPrimary : Colors.transparent, width: 2.5),
                  ),
                  child: current == hex ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        EditField(
          fieldKey: _k(d, 'color'),
          value: d.themeColor,
          label: '직접 고르기',
          hint: '#RRGGBB (예: #3B4A8C)',
          dense: true,
          onChanged: (v) => setState(() => d.themeColor = v.trim()),
        ),
        const Text('톡방 배경', style: AppTextStyles.speakerName),
        const SizedBox(height: 6),
        Row(children: [
          option('대표색 연하게', d.chatBackground != 'white', () => d.chatBackground = ''),
          option('흰색', d.chatBackground == 'white', () => d.chatBackground = 'white',
              key: const ValueKey('studio_bg_white')),
        ]),
        const SizedBox(height: AppSpacing.sm),
        const Text('내 말풍선', style: AppTextStyles.speakerName),
        const SizedBox(height: 6),
        Row(children: [
          option('대표색', d.bubbleStyle != 'pink', () => d.bubbleStyle = ''),
          option('기본 분홍', d.bubbleStyle == 'pink', () => d.bubbleStyle = 'pink'),
        ]),
        const SizedBox(height: AppSpacing.md),
        // 미리보기
        Container(
          key: const ValueKey('studio_color_preview'),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: theme.background, borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 대표색 윗줄 (대화방과 같게)
              Container(height: 3, color: theme.accent),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('${d.name.trim().isEmpty ? '말랑이' : d.name.trim()} 미리보기', style: AppTextStyles.messageTime),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: AppColors.partnerBubble, borderRadius: BorderRadius.circular(14)),
                        child: const Text('아직 안 자?', style: AppTextStyles.chatBubbleBody),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: theme.myBubble, borderRadius: BorderRadius.circular(14)),
                        child: Text('너야말로', style: AppTextStyles.chatBubbleBody.copyWith(color: theme.myText)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceWhite,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.choiceBorder, width: 1.2),
                      ),
                      child: const Text('선택지 테두리도 대표색', style: AppTextStyles.messageTime),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Text('글자색은 말풍선 밝기에 맞춰 흰색·검은색 중 잘 보이는 쪽으로 자동으로 바뀌어요.',
            style: AppTextStyles.messageTime),
      ],
    );
  }

  /// 7단계: AI로 생성하기 + 호감도 단계 + 대화 목록 (대화를 누르면 대사 편집)
  Widget _storyboardStep() {
    final d = _draft;
    final built = d.buildStages();
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFFBE7EF), Color(0xFFF1EAFB)]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('AI로 대본 만들기', style: AppTextStyles.choiceButton),
              const Text('1~6단계 설정을 읽고 대화 목차와 대사를 써요', style: AppTextStyles.messageTime),
              const SizedBox(height: 10),
              FilledButton.icon(
                key: const ValueKey('studio_ai_generate'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB83B66),
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: const Text('AI로 생성하기'),
                onPressed: _generating ? null : _openAiSheet,
              ),
              const SizedBox(height: 6),
              const Text('대화 옆 ✨를 누르면 그 대화만 다시 써요', style: AppTextStyles.messageTime),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        StudioCard(
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: const ValueKey('studio_stages'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text('호감도 단계 ${d.stages.length}개', style: AppTextStyles.choiceButton),
              subtitle: Text(
                built.map((s) => '${s.stageLabel} ${s.minScore}~${s.maxScore}').join(' → '),
                style: AppTextStyles.messageTime,
              ),
              children: [_stagesEditor()],
            ),
          ),
        ),
        ..._eventsList(),
      ],
    );
  }

  /// 8단계: 사진함 확인 + 작가 코멘트 + 공개
  /// 미리보기에서 다른 줄을 뽑을 때마다 바뀜
  int _previewSeed = 0;

  /// 4단계 성격 막대: 왼쪽 ↔ 오른쪽 낱말과 어느 쪽에 가까운지. 오른쪽을 비우면 한쪽짜리 (신중함 80%)
  Widget _traitsEditor() {
    final d = _draft;
    const examples = [('무심함', '다정함'), ('진지함', '장난기'), ('숨김', '솔직함'), ('겸손', '자존심'), ('쿨함', '질투')];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('성격', style: AppTextStyles.choiceButton),
        const Text('막대를 밀어 어느 쪽에 가까운지 정해요. 오른쪽을 비우면 한쪽짜리(신중함 80%). AI가 말투와 반응에 반영해요', style: AppTextStyles.messageTime),
        const SizedBox(height: 6),
        for (var i = 0; i < d.traits.length; i++)
          Padding(
            key: ValueKey(_k(d, 'trait-$i-${d.traits.length}')),
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: EditField(
                        fieldKey: _k(d, 'trait-l-$i-${d.traits.length}'),
                        value: d.traits[i].left,
                        hint: '왼쪽',
                        dense: true,
                        onChanged: (v) => d.traits[i] =
                            PersonalityTrait(left: v.trim(), right: d.traits[i].right, percent: d.traits[i].percent),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: EditField(
                        fieldKey: _k(d, 'trait-r-$i-${d.traits.length}'),
                        value: d.traits[i].right ?? '',
                        hint: '오른쪽',
                        dense: true,
                        onChanged: (v) => d.traits[i] = PersonalityTrait(
                            left: d.traits[i].left,
                            right: v.trim().isEmpty ? null : v.trim(),
                            percent: d.traits[i].percent),
                      ),
                    ),
                    IconButton(
                      tooltip: '빼기',
                      onPressed: () => setState(() {
                        d.traits.removeAt(i);
                        _version++;
                      }),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
                Slider(
                  key: ValueKey('trait_slider_$i'),
                  value: d.traits[i].percent.toDouble(),
                  max: 100,
                  divisions: 20,
                  label: '${d.traits[i].percent}%',
                  activeColor: const Color(0xFFB83B66),
                  onChanged: (v) => setState(() => d.traits[i] =
                      PersonalityTrait(left: d.traits[i].left, right: d.traits[i].right, percent: v.round())),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('studio_trait_add'),
            onPressed: () => setState(() {
              final used = {for (final t in d.traits) t.left};
              final next = examples.where((e) => !used.contains(e.$1)).firstOrNull;
              d.traits.add(next == null
                  ? const PersonalityTrait(left: '', right: '')
                  : PersonalityTrait(left: next.$1, right: next.$2));
              _version++;
            }),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('성격 추가'),
          ),
        ),
      ],
    );
  }

  /// 서비스 말랑이: 언제, 무슨 문구를 보낼지
  Widget _serviceStep(EdgeInsets pad) {
    final d = _draft;
    final s = d.service;
    void set(ServiceConfig c) => setState(() => d.service = c);
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    final holes = ['이름', '날짜', '요일', '숫자', ...s.columns.where((c) => c.trim().isNotEmpty)];
    final userName = ref.read(userProfileProvider).nickname;
    final preview = composeServiceMessage(
      s,
      userName: userName.isEmpty ? '다홍' : userName,
      charName: d.name.trim().isEmpty ? '말랑이' : d.name.trim(),
      now: DateTime.now(),
      random: Random(_previewSeed),
    );
    return ListView(
      padding: pad,
      children: [
        const Text('언제 보낼까요', style: AppTextStyles.speakerName),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Material(
                    color: s.days.contains(i + 1) ? AppColors.myBubble : AppColors.surfaceWhite,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: s.days.contains(i + 1) ? AppColors.primaryPink : const Color(0xFFE5D6DC)),
                    ),
                    child: InkWell(
                      key: ValueKey('studio_day_${i + 1}'),
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        final on = !s.days.contains(i + 1);
                        set(s.copyWith(
                          days: on ? ({...s.days, i + 1}.toList()..sort()) : [for (final x in s.days) if (x != i + 1) x],
                        ));
                      },
                      child: SizedBox(
                        height: 40,
                        child: Center(
                          child: Text(days[i],
                              style: AppTextStyles.choiceButton.copyWith(
                                  color: s.days.contains(i + 1) ? AppColors.primaryPink : AppColors.textMuted)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final t in s.times)
              InputChip(
                label: Text(serviceTimeLabel(t)),
                onDeleted: () => set(s.copyWith(times: [for (final x in s.times) if (x != t) x])),
              ),
            ActionChip(
              key: const ValueKey('studio_add_time'),
              avatar: const Icon(Icons.add_rounded, size: 16),
              label: const Text('시간 추가'),
              onPressed: () async {
                final picked = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 8, minute: 0));
                if (picked == null) return;
                final t = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                set(s.copyWith(times: ({...s.times, t}.toList()..sort())));
              },
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text('앱을 안 켜 둔 동안 온 톡은 대화방을 열면 쌓여 있어요', style: AppTextStyles.messageTime),
        const SizedBox(height: AppSpacing.lg),
        const Text('문구는 어떻게 만들까요', style: AppTextStyles.speakerName),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          key: const ValueKey('studio_service_mode'),
          segments: const [
            ButtonSegment(value: 'list', label: Text('문구 목록')),
            ButtonSegment(value: 'table', label: Text('데이터 표')),
            ButtonSegment(value: 'ai', label: Text('AI')),
          ],
          selected: {s.mode},
          showSelectedIcon: false,
          onSelectionChanged: (v) => set(s.copyWith(mode: v.first)),
        ),
        const SizedBox(height: 4),
        Text(
          switch (s.mode) {
            'table' => '표의 한 줄을 골라 아래 틀에 넣어서 보내요. 엑셀·구글 시트에서 칸째 복사해 붙여 넣으면 돼요',
            'ai' => '보낼 때마다 AI가 새로 써요. 대화방을 보는 사람의 AI 키를 써요',
            _ => '적어 둔 문구 중에서 랜덤으로 보내요. {이름}·{날짜}·{요일}·{숫자}를 넣을 수 있어요',
          },
          style: AppTextStyles.messageTime,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (s.mode == 'list')
          EditField(
            fieldKey: _k(d, 'svc_lines'),
            value: s.lines.join('\n'),
            label: '보낼 문구 (한 줄에 하나)',
            hint: '예: 이 편지를 받은 사람은 3일 안에 좋은 소식을 듣게 돼요!',
            lines: 6,
            onChanged: (v) => set(s.copyWith(lines: v.split('\n'))),
          ),
        if (s.mode == 'table') ...[
          EditField(
            fieldKey: _k(d, 'svc_table'),
            value: [s.columns.join('\t'), for (final r in s.rows) r.join('\t')].where((l) => l.isNotEmpty).join('\n'),
            label: '데이터 표 붙여 넣기 (첫 줄은 칸 이름)',
            hint: '띠\t운세\n쥐띠\t작은 친절이 큰 행운으로 돌아오는 날',
            lines: 5,
            onChanged: (v) {
              final t = parseServiceTable(v);
              set(s.copyWith(columns: t.columns, rows: t.rows));
            },
          ),
          if (s.columns.isNotEmpty) ...[
            Text('${s.rows.length}줄 · ${s.columns.length}칸', style: AppTextStyles.messageTime),
            const SizedBox(height: 4),
            Table(
              border: TableBorder.all(color: AppColors.borderLight),
              children: [
                TableRow(
                  decoration: const BoxDecoration(color: Color(0xFFF5EFF2)),
                  children: [for (final c in s.columns) _cell(c, bold: true)],
                ),
                for (final r in s.rows.take(3))
                  TableRow(children: [for (var i = 0; i < s.columns.length; i++) _cell(i < r.length ? r[i] : '')]),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          EditField(
            fieldKey: _k(d, 'svc_template-$_version'),
            value: s.template,
            label: '보낼 말 틀',
            hint: '예: {이름}! 오늘 {띠} 운세는… {운세} 행운의 숫자는 {숫자}',
            lines: 3,
            onChanged: (v) => set(s.copyWith(template: v)),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final h in holes)
                StudioPill(
                  label: '{$h}',
                  selected: false,
                  onTap: () => setState(() {
                    d.service = s.copyWith(template: '${s.template}{$h}');
                    _version++;
                  }),
                ),
            ],
          ),
        ],
        if (s.mode == 'ai')
          EditField(
            fieldKey: _k(d, 'svc_ai'),
            value: s.aiPrompt,
            label: 'AI에게 맡길 톡',
            hint: '예: 오늘의 운세를 띠 하나 골라서 짧고 다정하게. 행운의 숫자도 하나',
            lines: 3,
            onChanged: (v) => set(s.copyWith(aiPrompt: v)),
          ),
        if (s.mode != 'ai')
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('한 바퀴 돌 때까지 같은 문구 안 나오게', style: AppTextStyles.choiceButton),
            value: s.noRepeat,
            activeTrackColor: const Color(0xFFB83B66),
            onChanged: (v) => set(s.copyWith(noRepeat: v)),
          ),
        SwitchListTile(
          key: const ValueKey('studio_service_reroll'),
          contentPadding: EdgeInsets.zero,
          title: const Text("대화방에 '한 번 더 뽑기' 버튼", style: AppTextStyles.choiceButton),
          subtitle: const Text('누를 때마다 새 문구가 와요', style: AppTextStyles.messageTime),
          value: s.reroll,
          activeTrackColor: const Color(0xFFB83B66),
          onChanged: (v) => set(s.copyWith(reroll: v)),
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text('미리보기', style: AppTextStyles.speakerName),
        const SizedBox(height: 6),
        Container(
          key: const ValueKey('studio_service_preview'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F2F7),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(14),
              bottomLeft: Radius.circular(14),
              bottomRight: Radius.circular(14),
            ),
          ),
          child: Text(
            s.mode == 'ai'
                ? '(보낼 때마다 AI가 새로 써요)'
                : preview?.text ?? '문구를 적으면 여기에 보여요',
            style: AppTextStyles.chatBubbleBody,
          ),
        ),
        if (s.mode != 'ai')
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _previewSeed++),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('다른 문구로 미리보기'),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        EditField(
          fieldKey: _k(d, 'svc_setting'),
          value: d.setting,
          label: '캐릭터 설정 · 말투 (답장할 때 AI가 참고)',
          hint: '예: 운세를 알려 주는 떡 요정. 반말, 밝고 수다스러움',
          lines: 3,
          onChanged: (v) => d.setting = v,
        ),
      ],
    );
  }

  Widget _cell(String text, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.messageTime.copyWith(
                color: AppColors.textPrimary, fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
      );

  Widget _finishStep() {
    final d = _draft;
    final withPhotos = [for (final e in d.events) if (e.photoSlots.isNotEmpty) e];
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl),
      children: [
        if (!d.isService) ...[
          CharacterPhotoBox(
            key: ValueKey('photo_box_$_version'),
            draft: d,
            onChanged: () => setState(() {}),
            onOpenEvent: (e) => setState(() {
              _scriptEvent = e;
              _step = 6;
            }),
          ),
          if (withPhotos.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            const Text('사진이 들어갈 대화', style: AppTextStyles.speakerName),
            const Text('누르면 그 대화의 대사 편집으로 가요', style: AppTextStyles.messageTime),
            const SizedBox(height: 6),
          ],
          for (final e in withPhotos)
            StudioCard(
              child: InkWell(
                onTap: () => setState(() {
                  _scriptEvent = e;
                  _step = 6;
                }),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${d.events.indexOf(e) + 1}. ${e.title.trim().isEmpty ? '(제목 없음)' : e.title}',
                              style: AppTextStyles.chatBubbleBody.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Wrap(spacing: 4, runSpacing: 4, children: _photoTags(e)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: AppSpacing.md),
        EditField(
          fieldKey: _k(d, 'author'),
          value: d.authorComment,
          label: '작가 코멘트 · 상세 화면 맨 아래',
          hint: '예) 첫 캐릭터예요! 진지할 때 말이 짧아지니 그때를 잘 봐 주세요…',
          lines: 4,
          onChanged: (v) => d.authorComment = v,
        ),
        SwitchListTile(
          key: const ValueKey('studio_publish'),
          contentPadding: EdgeInsets.zero,
          title: const Text('말랑이 찾기에 올리기', style: AppTextStyles.choiceButton),
          subtitle: const Text('끄면 내 말랑이에서만 보여요', style: AppTextStyles.messageTime),
          value: !d.unlisted,
          activeTrackColor: const Color(0xFFB83B66),
          onChanged: (v) => setState(() => d.unlisted = !v),
        ),
      ],
    );
  }

  /// '빈 칸 AI로 채우기': 이 단계에서 비어 있는 칸만 AI가 써 넣음 (적어 둔 칸은 그대로)
  Future<void> _fillBlanks(List<String> fields) async {
    final d = _draft;
    if (d.name.trim().isEmpty) {
      _toast('기본 단계에서 이름을 먼저 적어 주세요');
      return _goStep(0);
    }
    if (d.setting.trim().length < 10) {
      _toast('이야기 단계의 캐릭터 설정을 조금 더 적어 주면 AI가 그에 맞게 채워요');
      setState(() => _storyPart = 0);
      return _goStep(4);
    }
    final byok = ref.read(byokSettingsProvider);
    if (!byok.canUseAi) return _toast('설정 > AI 연결에서 AI 키를 먼저 넣어 주세요');
    final empty = [
      for (final f in fields)
        if (switch (f) {
          'profile_fields' => d.fields.every((x) => x.value.trim().isEmpty),
          'quote' => d.quote.trim().isEmpty,
          'sample_quotes' => d.sampleQuotes.every((q) => q.body.trim().isEmpty),
          'traits' => d.traits.isEmpty,
          'world_setting' => d.world.trim().isEmpty,
          'user_role' => d.userRole.trim().isEmpty,
          'extra_cast' => d.cast.every((c) => c.name.trim().isEmpty),
          'secret' => d.secret.trim().isEmpty,
          _ => false,
        })
          f,
    ];
    if (empty.isEmpty) return _toast('이 단계엔 빈 칸이 없어요');
    setState(() {
      _generating = true;
      _progress = null;
      _progressText = '빈 칸을 채우는 중';
    });
    try {
      final json = await ref.read(claudeStudioClientProvider).fillBlanks(
            provider: byok.provider,
            apiKey: byok.apiKey ?? '',
            relay: byok.relay,
            model: byok.model,
            character: d.buildCharacter(),
            fields: empty,
          );
      if (!mounted) return;
      String text(String key) => (json[key] as String? ?? '').trim();
      List<Map> list(String key) => [for (final x in json[key] as List? ?? const []) if (x is Map) x];
      setState(() {
        if (json.containsKey('profile_fields')) {
          d.fields
            ..removeWhere((x) => x.value.trim().isEmpty)
            ..addAll([
              for (final x in list('profile_fields'))
                FieldDraft(label: '${x['label'] ?? ''}'.trim(), value: '${x['value'] ?? ''}'.trim()),
            ]);
        }
        if (json.containsKey('quote')) d.quote = text('quote');
        if (json.containsKey('sample_quotes')) {
          d.sampleQuotes = [
            for (final x in list('sample_quotes'))
              CharacterQuote(situation: '${x['situation'] ?? ''}'.trim(), body: '${x['body'] ?? ''}'.trim()),
          ];
        }
        if (json.containsKey('traits')) {
          d.traits = [for (final x in list('traits')) PersonalityTrait.fromJson(Map<String, dynamic>.from(x))];
        }
        if (json.containsKey('world_setting')) d.world = text('world_setting');
        if (json.containsKey('user_role')) d.userRole = text('user_role');
        if (json.containsKey('extra_cast')) {
          d.cast
            ..removeWhere((c) => c.name.trim().isEmpty)
            ..addAll([
              for (final x in list('extra_cast'))
                CastDraft(name: '${x['name'] ?? ''}'.trim(), role: '${x['role'] ?? ''}'.trim()),
            ]);
        }
        if (json.containsKey('secret')) d.secret = text('secret');
        _version++;
      });
      _toast('빈 칸 ${empty.length}곳을 채웠어요. 마음에 안 들면 고쳐 써 주세요');
    } on ClaudeChatException catch (e) {
      if (mounted) _toast(e.message);
    } catch (e) {
      if (mounted) _toast('채우는 중 문제가 생겼어요: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
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
                  if (e.characterId != null)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Tooltip(
                        message: '내 캐릭터와 연결됨',
                        child: Icon(Icons.link_rounded, size: 18, color: AppColors.primaryPink),
                      ),
                    ),
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
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _pickMyCharacterAsCast,
              icon: const Icon(Icons.link_rounded, size: 18),
              label: const Text('내가 만든 캐릭터 연결'),
            ),
          ),
        ],
      ),
    );
  }

  /// 내가 만든 다른 캐릭터를 골라 주변 인물로 연결 (이름·한줄 소개를 채워 줌, 관계는 직접 고쳐 써요)
  Future<void> _pickMyCharacterAsCast() async {
    final d = _draft;
    final linked = {for (final e in d.cast) e.characterId};
    final mine = ref
        .read(characterLibraryProvider)
        .where((e) => e.source == CharacterSource.created && e.id != d.id && !linked.contains(e.id))
        .map((e) => e.bundle.character)
        .toList();
    final picked = await showModalBottomSheet<CharacterModel>(
      context: context,
      backgroundColor: AppColors.surfaceWhite,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: mine.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('연결할 수 있는 내가 만든 캐릭터가 없어요', textAlign: TextAlign.center, style: AppTextStyles.systemNotice),
              )
            : ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text('주변 인물로 연결할 내 캐릭터', style: AppTextStyles.appBarTitle),
                  ),
                  for (final c in mine)
                    ListTile(
                      leading: CharacterAvatar(character: c, radius: 20),
                      title: Text(c.name),
                      subtitle: c.tagline.isEmpty ? null : Text(c.tagline, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.pop(ctx, c),
                    ),
                ],
              ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => d.cast.add(CastDraft(name: picked.name, role: picked.tagline, characterId: picked.id)));
  }

  // ───────────────────────── 호감도 단계 탭 ─────────────────────────

  Widget _stagesEditor() {
    final d = _draft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: AppSpacing.sm),
          child: Text(
            '관계가 깊어지는 단계예요. 이름과 시작 점수(0~100)를 정해요. 첫 단계는 0점부터. '
            '플레이어에겐 숫자 없이 단계 이름과 차오르는 말랑이로만 보여요.',
            style: AppTextStyles.messageTime,
          ),
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
      ],
    );
  }

  // ───────────────────────── 이벤트 탭 ─────────────────────────

  List<Widget> _eventsList() {
    final d = _draft;
    return [
        const StudioSection(
          title: '대화',
          note: '위에서부터 순서대로 진행돼요. 대화를 펼쳐 종류·단계·사진을 고치고, 대사 편집에서 말풍선을 써요.',
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
                    // 엔딩·공략 후 이야기는 맨 끝, 나머지는 엔딩 앞에
                    final endingAt = d.events.indexWhere((e) => e.kind == DraftKind.ending);
                    if (kind == DraftKind.ending || kind == DraftKind.afterEnding || endingAt < 0) {
                      d.events.add(event);
                    } else {
                      d.events.insert(endingAt, event);
                    }
                  }),
                ),
          ],
        ),
    ];
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
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '이 대화만 AI로 다시 쓰기',
                visualDensity: VisualDensity.compact,
                onPressed: _generating ? null : () => _generateOne(e),
                icon: const Icon(Icons.auto_awesome_rounded, size: 18, color: Color(0xFFB83B66)),
              ),
              const Icon(Icons.expand_more_rounded),
            ],
          ),
          title: Text(
            '${index + 1}. ${e.title.trim().isEmpty ? '(제목 없음)' : e.title}',
            style: AppTextStyles.chatBubbleBody.copyWith(fontWeight: FontWeight.w700),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [
                  e.kind.label,
                  if (e.kind.needsStage && e.stage.isNotEmpty) e.stage,
                  if (e.follows.isNotEmpty && e.kind.canFollow) '이어지는 대화',
                  if (e.kind == DraftKind.special) _windowLabel(e),
                  if (e.kind != DraftKind.special && e.notice.isNotEmpty) e.notice,
                  '말풍선 $lines개',
                ].join(' · '),
                style: AppTextStyles.messageTime,
              ),
              if (_photoTags(e) case final tags when tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(spacing: 4, runSpacing: 4, children: tags),
                ),
            ],
          ),
          children: [
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<DraftKind>(
                    initialValue: e.kind,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '종류', isDense: true),
                    items: [for (final k in DraftKind.values) DropdownMenuItem(value: k, child: Text(k.label))],
                    onChanged: (k) => setState(() => e.kind = k ?? e.kind),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (e.kind.needsStage)
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(_k(e, 'stage-${d.stageNames.join('|')}')),
                      isExpanded: true,
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
            if (e.kind.canFollow)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: DropdownButtonFormField<String>(
                  key: ValueKey(_k(e, 'follows-${d.events.length}')),
                  isExpanded: true,
                  initialValue: d.events.any((o) => o.id == e.follows && o != e) ? e.follows : '',
                  decoration: const InputDecoration(
                    labelText: '이어지는 대화',
                    helperText: '고르면 그 대화가 끝난 바로 뒤에 와요. 안 고른 일상 대화는 무작위 순서로 와요',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('따로 (이어지지 않음)')),
                    for (var j = 0; j < d.events.length; j++)
                      if (d.events[j] != e && d.events[j].kind != DraftKind.special)
                        DropdownMenuItem(
                          value: d.events[j].id,
                          child: Text(
                            '${j + 1}. ${d.events[j].title.trim().isEmpty ? '(제목 없음)' : d.events[j].title.trim()} 다음에',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                  ],
                  onChanged: (v) => setState(() => e.follows = v ?? ''),
                ),
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
            if (e.kind != DraftKind.daily) ...[
              const Text('컷씬 사진 · 사진함에서 골라요', style: AppTextStyles.speakerName),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: EventPhotoPicker(
                  photos: d.photos,
                  selected: e.cutsceneImage,
                  note: '고르지 않으면 설명 카드로 보여요',
                  onAdd: (v) => setState(() => d.addPhoto(v)),
                  onSelect: (v) => setState(() => e.cutsceneImage = v),
                ),
              ),
            ],
            Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.edit_note_rounded, size: 18),
                  label: const Text('대사 편집'),
                  onPressed: () => setState(() => _scriptEvent = e),
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
    final hasCutscene = event.hasCutscene;
    // 수정하러 가기로 아래쪽 말풍선까지 스크롤하려면 전부 그려 둬야 해서 ListView 대신 Column
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('studio_script_back'),
              onPressed: () => setState(() => _scriptEvent = null),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('대화 목록'),
            ),
          ),
          DropdownButtonFormField<EventDraft>(
            key: ValueKey(_k(event, 'picker-${d.events.length}')),
            initialValue: event,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '편집할 대화', isDense: true),
            items: [
              for (var i = 0; i < d.events.length; i++)
                DropdownMenuItem(
                  value: d.events[i],
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${i + 1}. ${d.events[i].title.trim().isEmpty ? '(제목 없음)' : d.events[i].title} · ${d.events[i].kind.label}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (d.events[i].photoSlots.isNotEmpty)
                        Icon(
                          d.events[i].photoSlots.any((s) => _photoState(s) == PhotoState.missing)
                              ? Icons.warning_amber_rounded
                              : Icons.image_rounded,
                          size: 16,
                          color: d.events[i].photoSlots.any((s) => _photoState(s) == PhotoState.missing)
                              ? AppColors.affectionWarm
                              : AppColors.primaryPink,
                        ),
                    ],
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
          _photoSummary(event),
          for (var i = 0; i < event.scenes.length; i++) _sceneCard(event, i, hasCutscene),
          OutlinedButton.icon(
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('장면 추가'),
            onPressed: () => setState(() => event.scenes.add(SceneDraft())),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  /// 대사 탭 맨 위: 캐릭터 사진함 바로 가기, 컷씬 사진, 사진 말풍선이 채워졌는지
  Widget _photoSummary(EventDraft event) {
    final cut = event.photoSlots.where((s) => s.isCutscene).firstOrNull;
    return StudioCard(
      key: _jumpKey(event),
      highlight: cut != null && _photoState(cut) == PhotoState.missing,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Text('이 대화의 사진', style: AppTextStyles.speakerName)),
              Flexible(child: Wrap(spacing: 4, runSpacing: 4, alignment: WrapAlignment.end, children: _photoTags(event))),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Text('사진은 캐릭터 사진함 ${_draft.photos.length}장에서 골라요. 설명이 같으면 저절로 붙어요',
                    style: AppTextStyles.messageTime),
              ),
              TextButton(onPressed: () => _goStep(7), child: const Text('사진함 열기')),
            ],
          ),
          if (cut != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('컷씬 사진 · ${cut.label}', style: AppTextStyles.speakerName, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            EventPhotoPicker(
              photos: _draft.photos,
              selected: event.cutsceneImage,
              note: _photoStateText(_photoState(cut)),
              onAdd: (v) => setState(() => _draft.addPhoto(v)),
              onSelect: (v) => setState(() => event.cutsceneImage = v),
            ),
          ],
        ],
      ),
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
              if (scene.lines.where((l) => l.isPhoto).length case final n when n > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: PhotoTag(
                    label: '사진 $n',
                    state: event.photoSlots
                            .any((s) => s.sceneIndex == index && _photoState(s) == PhotoState.missing)
                        ? PhotoState.missing
                        : PhotoState.filled,
                  ),
                ),
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
          EditField(
            fieldKey: _k(scene, 'userFirst'),
            value: scene.userFirst,
            label: '선톡 (선택)',
            hint: '캐릭터보다 내가 먼저 보내는 톡. 줄마다 말풍선 하나. 비우면 캐릭터가 먼저 말해요',
            lines: 2,
            onChanged: (v) => scene.userFirst = v,
          ),
          const Text('캐릭터 말풍선', style: AppTextStyles.speakerName),
          const SizedBox(height: 4),
          for (final line in scene.lines) _lineRow(event, scene, line),
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

  Widget _lineRow(EventDraft event, SceneDraft scene, LineDraft line) {
    final speeds = <double, String>{0.6: '툭 빠르게', 1.0: '보통', 1.5: '망설이며'};
    final speedKey = speeds.keys.reduce((a, b) => (a - line.speed).abs() <= (b - line.speed).abs() ? a : b);
    final slot = line.isPhoto ? event.photoSlots.firstWhere((s) => s.line == line) : null;
    final state = slot == null ? null : _photoState(slot);
    final stateColor = state == null ? null : PhotoTag.colorOf(state);
    // 사진 말풍선은 색 테두리로 감싸서 눈에 띄게 (안 고른 곳은 주황)
    return Container(
      key: _jumpKey(line),
      margin: const EdgeInsets.only(bottom: 6),
      padding: slot == null ? EdgeInsets.zero : const EdgeInsets.fromLTRB(6, 4, 0, 6),
      decoration: slot == null
          ? null
          : BoxDecoration(
              color: stateColor!.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: stateColor.withValues(alpha: state == PhotoState.missing ? 0.9 : 0.4),
                  width: state == PhotoState.missing ? 1.5 : 1),
            ),
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
                // 누를 때마다 바로 → 늦게(10초) → 한참 뒤(30초)
                tooltip: switch (line.delay) { 0 => '답장 늦게 오게', 10 => '답장 늦게 (10초)', _ => '답장 한참 뒤에 (30초)' },
                onPressed: () => setState(() => line.delay = switch (line.delay) { 0 => 10, 10 => 30, _ => 0 }),
                icon: Badge(
                  isLabelVisible: line.delay > 0,
                  label: Text('${line.delay}'),
                  child: Icon(Icons.schedule_rounded, size: 20,
                      color: line.delay == 0 ? AppColors.textMuted : AppColors.primaryPink),
                ),
              ),
              IconButton(
                tooltip: line.isPhoto ? '사진 빼기' : '사진 말풍선으로',
                onPressed: () => setState(() {
                  final on = !line.isPhoto;
                  line.photo = on ? '사진' : '';
                  if (!on) line.photoImage = '';
                  _version++;
                }),
                icon: Icon(line.isPhoto ? Icons.image_rounded : Icons.image_outlined, size: 20,
                    color: stateColor ?? AppColors.textMuted),
              ),
              IconButton(
                tooltip: '말풍선 빼기',
                onPressed: scene.lines.length > 1 ? () => setState(() => scene.lines.remove(line)) : null,
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
            ],
          ),
          if (slot != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 96),
              child: EditField(fieldKey: _k(line, 'photo'), value: line.photo, hint: '보내는 사진 설명', dense: true,
                  onChanged: (v) => line.photo = v),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: PhotoTag(label: '사진 말풍선 · ${_photoStateText(state!)}', state: state),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: EventPhotoPicker(
                photos: _draft.photos,
                selected: line.photoImage,
                note: state == PhotoState.shared ? '고르지 않으면 설명이 같은 사진이 나와요' : '고르지 않으면 설명 카드로 보여요',
                onAdd: (v) => setState(() => _draft.addPhoto(v)),
                onSelect: (v) => setState(() => line.photoImage = v),
              ),
            ),
          ],
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

/// 캐릭터 사진함에서 하나 고르기 (누르면 고르고, 고른 걸 다시 누르면 빼기). 새로 올리면 사진함에도 들어가고 바로 골라짐
class EventPhotoPicker extends StatelessWidget {
  const EventPhotoPicker({
    super.key,
    required this.photos,
    required this.selected,
    required this.note,
    required this.onAdd,
    required this.onSelect,
  });

  final List<String> photos;
  final String selected;
  final String note;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final p in photos)
          if (CharacterImage.providerFor(p) case final provider?)
            GestureDetector(
              onTap: () => onSelect(p == selected ? '' : p),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: p == selected ? AppColors.primaryPink : Colors.transparent,
                    width: 2.5,
                  ),
                ),
                child: Opacity(
                  opacity: selected.isEmpty || p == selected ? 1 : 0.45,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image(image: provider, width: 48, height: 48, fit: BoxFit.cover),
                  ),
                ),
              ),
            ),
        TextButton.icon(
          icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
          label: const Text('새로 올리기'),
          onPressed: () async {
            final picked = await pickPhoto(context);
            if (picked == null) return;
            onAdd(picked);
            onSelect(picked);
          },
        ),
        if (selected.isEmpty) Text(note, style: AppTextStyles.messageTime),
      ],
    );
  }
}

