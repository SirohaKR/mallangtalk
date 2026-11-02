import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/claude_chat_client.dart';
import '../../core/network/conversation_context.dart';
import '../../core/storage/local_store.dart';
import '../../shared/models/mallangtalk_models.dart';
import '../chat/chat_notifier.dart';
import '../chat/romance_settings.dart';
import '../settings/byok_settings.dart';
import '../settings/user_profile.dart';

/// [초보자 노트] 현실 장면 방: 톡 말풍선을 꾹 눌러 '현실 장면으로'를 고르면, 그 톡 바로 뒤에
/// 둘이 실제로 마주한 장면을 AI가 로판 웹소설처럼 지문(괄호)+대사로 써 주는 방이에요.
/// - 톡 방(스토리 방 ID 또는 ID#free)마다 하나. 기록은 scene_<톡 방 ID>에 저장(계정 연동).
/// - 로어북은 그 톡 방과 같이 써요: 장면을 쓸 때 톡 방 로어북을 넘기고, 장면 요약도 톡 방 로어북에 쌓여요.
/// - 한 번 답할 때마다 공백 포함 1900자 이상(모자라면 AI에게 이어 쓰게 함), 내 입력은 1000자까지.

/// 장면 한 줄
class SceneLine {
  /// user: 내 입력 / story: AI가 쓴 장면 / start: 새 장면 시작(어느 톡에서) / notice: 안내
  final String kind;
  final String id;
  final String text;

  /// start 줄만: 장면이 시작된 톡 기록 (AI에게 넘김)
  final String context;
  final DateTime at;

  const SceneLine({
    required this.kind,
    required this.id,
    required this.text,
    this.context = '',
    required this.at,
  });

  bool get isUser => kind == 'user';
  bool get isStory => kind == 'story';
  bool get isStart => kind == 'start';

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'id': id,
        'text': text,
        if (context.isNotEmpty) 'context': context,
        'at': at.toIso8601String(),
      };

  factory SceneLine.fromJson(Map<String, dynamic> j) => SceneLine(
        kind: j['kind'] as String? ?? 'notice',
        id: j['id'] as String? ?? '',
        text: j['text'] as String? ?? '',
        context: j['context'] as String? ?? '',
        at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime(2026),
      );
}

class SceneState {
  final List<SceneLine> lines;

  /// AI가 장면을 쓰는 중
  final bool writing;

  /// 마지막으로 실패한 이유 (다시 시도 버튼과 함께)
  final String? error;

  const SceneState({this.lines = const [], this.writing = false, this.error});

  bool get isEmpty => lines.isEmpty;

  /// 지금 진행 중인 장면이 있는지 (마지막 시작 뒤에 '장면 끝' 안내가 없으면)
  bool get sceneOpen {
    final start = lines.lastIndexWhere((l) => l.isStart);
    if (start < 0) return false;
    return !lines.skip(start + 1).any((l) => l.kind == 'notice' && l.id.startsWith('end_'));
  }

  SceneLine? get lastStory => lines.where((l) => l.isStory).lastOrNull;

  SceneState copyWith({List<SceneLine>? lines, bool? writing, String? error, bool clearError = false}) => SceneState(
        lines: lines ?? this.lines,
        writing: writing ?? this.writing,
        error: clearError ? null : (error ?? this.error),
      );
}

/// 현실 장면 방 (인자: 톡 방 ID)
class SceneRoomNotifier extends FamilyNotifier<SceneState, String> {
  late LocalStore _store;
  String? _loreUptoId;
  bool _summarizing = false;
  int _seq = 0;

  /// 몇 번 주고받을 때마다 장면을 요약해 로어북에 넣을지
  static const loreEveryTurns = 3;

  /// AI에게 그대로 넘기는 지난 장면 줄 수 (내 입력·AI 장면 합쳐서). 그보다 앞은 로어북 요약으로 넘어감
  static const recentLines = 4;

  String get _sourceRoom => arg;
  String get _characterId => characterIdOfRoom(arg);

  @override
  SceneState build(String sourceRoomId) {
    _store = ref.watch(localStoreProvider);
    final raw = _store.loadScene(sourceRoomId);
    if (raw == null) return const SceneState();
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _loreUptoId = j['lore_upto'] as String?;
      return SceneState(lines: [
        for (final l in j['lines'] as List? ?? const []) SceneLine.fromJson(Map<String, dynamic>.from(l as Map)),
      ]);
    } catch (_) {
      return const SceneState();
    }
  }

  DateTime _now() => ref.read(clockProvider)();
  String _newId(String kind) => '${kind}_${_now().microsecondsSinceEpoch}_${_seq++}';

  void _save() => _store.saveScene(
      _sourceRoom,
      state.lines.isEmpty
          ? null
          : jsonEncode({
              'lines': [for (final l in state.lines) l.toJson()],
              if (_loreUptoId != null) 'lore_upto': _loreUptoId,
            }));

  void _add(SceneLine line) {
    state = state.copyWith(lines: [...state.lines, line]);
    _save();
  }

  CharacterModel get _character => ref.read(chatRoomProvider(_sourceRoom)).character;
  String get _nickname => ref.read(chatNicknameProvider(_characterId));
  ByokSettings get _byok => ref.read(roomByokProvider(sceneAiRoom(_sourceRoom)));

  /// 톡 방 로어북 (같이 씀)
  List<String> get sharedMemories => ref.read(chatRoomProvider(_sourceRoom)).memories;

  String get _persona => [
        ref.read(chatPersonaProvider(_characterId)),
        if (isFreeRoom(_sourceRoom)) romanceDirection(ref.read(romanceSettingsProvider(_characterId)), _character),
      ].where((s) => s.isNotEmpty).join('\n\n');

  /// 톡 방의 [messageId] 톡에서 새 장면을 시작함 (그 톡까지 최근 16개를 장면의 앞 맥락으로)
  Future<void> startFrom(String messageId) async {
    if (state.writing) return;
    final messages = ref.read(chatRoomProvider(_sourceRoom)).messages;
    final index = messages.indexWhere((m) => m.id == messageId);
    if (index < 0) return;
    final picked = messages[index];
    final before = [
      for (final m in messages.take(index + 1))
        if (!m.isSystem && !m.isHidden) m,
    ];
    final context = conversationTranscript(
        before.reversed.take(16).toList().reversed.toList(), _nickname, _character.name);
    if (state.sceneOpen) endScene(); // 앞 장면 요약은 뒤에서 (새 장면은 바로 시작)
    final excerpt = picked.text.trim().isEmpty ? (picked.hasPhoto ? '사진' : '톡') : picked.text.trim();
    _add(SceneLine(
      kind: 'start',
      id: _newId('start'),
      text: excerpt.length > 40 ? '${excerpt.substring(0, 40)}…' : excerpt,
      context: context,
      at: _now(),
    ));
    await _write();
  }

  /// 내 행동(괄호)·대사를 보내고 다음 장면을 받음
  bool send(String text) {
    final t = text.trim();
    if (t.isEmpty || state.writing || !state.sceneOpen) return false;
    _add(SceneLine(
      kind: 'user',
      id: _newId('user'),
      text: t.length > ClaudeChatClient.sceneInputMaxChars ? t.substring(0, ClaudeChatClient.sceneInputMaxChars) : t,
      at: _now(),
    ));
    _write();
    return true;
  }

  /// 실패한 장면 다시 쓰기
  Future<void> retry() => _write();

  /// 내 입력 [userLineId]와 그에 대한 AI 장면이 차지하는 칸 [i, end) (다음 내 입력·장면 시작·안내 전까지)
  ({int index, int end})? _turn(String userLineId) {
    final i = state.lines.indexWhere((l) => l.id == userLineId);
    if (i < 0 || !state.lines[i].isUser) return null;
    var end = i + 1;
    while (end < state.lines.length && state.lines[end].isStory) end++;
    return (index: i, end: end);
  }

  /// 다시 받기는 진행 중인 장면의 맨 마지막 내 입력에만
  bool canResend(String userLineId) {
    if (state.writing || !state.sceneOpen) return false;
    final t = _turn(userLineId);
    return t != null && t.end == state.lines.length;
  }

  void _removeLines(int start, int end) {
    final removed = {for (final l in state.lines.sublist(start, end)) l.id};
    if (_loreUptoId != null && removed.contains(_loreUptoId)) {
      final before = state.lines.take(start).where((l) => l.isUser || l.isStory).lastOrNull;
      _loreUptoId = before?.id;
    }
    state = state.copyWith(lines: [...state.lines.sublist(0, start), ...state.lines.sublist(end)], clearError: true);
  }

  /// 쓰레기통: 내 입력과 그 뒤 AI 장면을 지움 (로어북에 들어간 요약은 그대로)
  void deleteTurn(String userLineId) {
    if (state.writing) return;
    final t = _turn(userLineId);
    if (t == null) return;
    _removeLines(t.index, t.end);
    _save();
  }

  /// 재전송: 마지막 내 입력은 그대로 두고 그 뒤 AI 장면만 지운 뒤 다시 씀
  Future<void> resend(String userLineId) async {
    if (!canResend(userLineId)) return;
    final t = _turn(userLineId)!;
    _removeLines(t.index + 1, t.end);
    _save();
    await _write();
  }

  /// 재전송하면 드는 어림 비용 (지금 장면을 지운 상태로 셈)
  ({int inputTokens, int outputTokens, double? won, double? maxWon}) estimateResend(String userLineId) {
    final t = _turn(userLineId);
    if (t == null) return estimate('');
    return estimate('', lines: state.lines.sublist(0, t.index + 1));
  }

  /// 지금 장면에서 AI에게 넘길 것: 시작 줄, 그 뒤 줄들, 마지막 내 입력
  ({SceneLine? start, List<SceneLine> scene, String? input}) _current([List<SceneLine>? all]) {
    final lines = all ?? state.lines;
    final s = lines.lastIndexWhere((l) => l.isStart);
    if (s < 0) return (start: null, scene: const [], input: null);
    final after = lines.skip(s + 1).where((l) => l.isUser || l.isStory).toList();
    final input = after.isNotEmpty && after.last.isUser ? after.removeLast().text : null;
    // 장면이 길어질수록 다시 보내는 글이 불어나서 비용이 커짐: 로어북에 요약된 앞부분은 빼고, 최근 [recentLines]줄만
    final upto = after.indexWhere((l) => l.id == _loreUptoId);
    var recent = after.skip(upto + 1).toList();
    // 방금 요약했어도 바로 앞 장면(내 입력+AI 장면)은 그대로 넘겨 이어지게
    if (recent.length < 2) recent = after.length > 2 ? after.sublist(after.length - 2) : after;
    final scene = recent.length > recentLines ? recent.sublist(recent.length - recentLines) : recent;
    return (start: lines[s], scene: scene, input: input);
  }

  Future<void> _write() async {
    final cur = _current();
    final start = cur.start;
    if (start == null || state.writing) return;
    final byok = _byok;
    if (!byok.canUseAi) {
      state = state.copyWith(error: '현실 장면은 AI가 써요. 설정 › AI 연결에서 AI 키를 넣어 주세요.');
      return;
    }
    state = state.copyWith(writing: true, clearError: true);
    try {
      final text = await ref.read(claudeChatClientProvider).sceneTurn(
            provider: byok.provider,
            apiKey: byok.apiKey ?? '',
            relay: byok.relay,
            model: byok.model,
            character: _character,
            userName: _nickname,
            userIntro: ref.read(userProfileProvider).intro,
            userPersona: _persona,
            memories: sharedMemories,
            talkContext: start.context,
            scene: [for (final l in cur.scene) (isUser: l.isUser, text: l.text)],
            userInput: cur.input,
          );
      state = state.copyWith(writing: false);
      _add(SceneLine(kind: 'story', id: _newId('story'), text: text, at: _now()));
      _maybeSummarize();
    } on ClaudeChatException catch (e) {
      state = state.copyWith(writing: false, error: e.message);
    } catch (_) {
      state = state.copyWith(writing: false, error: 'AI 장면을 받지 못했어요. 다시 해 주세요.');
    }
  }

  /// 장면을 마침: 아직 요약 안 한 부분을 로어북에 넣고 '장면 끝' 표시
  Future<void> endScene() async {
    if (!state.sceneOpen) return;
    _add(SceneLine(kind: 'notice', id: _newId('end'), text: '장면이 끝났어요', at: _now()));
    await _maybeSummarize(force: true);
  }

  /// 현실 장면 방을 비움 (로어북은 톡 방에 그대로 남음)
  void clear() {
    _loreUptoId = null;
    state = const SceneState();
    _save();
  }

  /// 지난 요약 뒤로 [loreEveryTurns]번 이상(장면을 마칠 때는 1번 이상) 장면을 받았으면 요약해 톡 방 로어북에 더함
  Future<void> _maybeSummarize({bool force = false}) async {
    if (_summarizing) return;
    final start = _loreUptoId == null ? 0 : state.lines.indexWhere((l) => l.id == _loreUptoId) + 1;
    final part = state.lines.skip(start).where((l) => l.isUser || l.isStory).toList();
    final stories = part.where((l) => l.isStory).length;
    if (stories < (force ? 1 : loreEveryTurns)) return;
    final byok = _byok;
    if (!byok.canUseAi) return;
    _summarizing = true;
    final upto = part.last.id;
    final character = _character;
    try {
      final note = await ref.read(claudeChatClientProvider).summarizeLore(
            provider: byok.provider,
            apiKey: byok.apiKey ?? '',
            relay: byok.relay,
            model: byok.model,
            character: character,
            messages: [
              for (final l in part)
                ChatMessageLog(
                  id: l.id,
                  isUser: l.isUser,
                  speakerCharacterId: l.isUser ? 'user' : character.id,
                  speakerName: l.isUser ? _nickname : character.name,
                  text: l.isUser ? l.text : '[현실 장면] ${l.text}',
                  timestamp: l.at,
                ),
            ],
            userName: _nickname,
            previous: sharedMemories,
          );
      _loreUptoId = upto;
      final title = note.title.isEmpty ? '현실 장면' : '현실 · ${note.title}';
      ref.read(chatRoomProvider(_sourceRoom).notifier).setMemories(
          [...sharedMemories, MemoryNote(title: title, detail: note.detail).encode()]);
      _save();
    } on ClaudeChatException {
      // 다음에 다시 요약함
    } catch (_) {
    } finally {
      _summarizing = false;
    }
  }

  /// 다음에 보낼 때 드는 어림 비용. 한글은 1글자 ≈ 1토큰으로 넉넉히 잡음
  ({int inputTokens, int outputTokens, double? won, double? maxWon}) estimate(String input, {List<SceneLine>? lines}) {
    final cur = _current(lines);
    final sheet = _character.aiCharacterSheet.length;
    final memories = sharedMemories.fold<int>(0, (n, m) => n + m.length + 4);
    final context = cur.start?.context.length ?? 0;
    final scene = cur.scene.fold<int>(0, (a, l) => a + l.text.length);
    final inputTokens =
        1800 + sheet + memories + context + scene + _persona.length + input.trim().length + (cur.input?.length ?? 0);
    // 1900~2600자 + JSON 모양 ≈ 3천 토큰
    const outputTokens = 3000;
    final m = _byok.modelOption;
    if (m == null) return (inputTokens: inputTokens, outputTokens: outputTokens, won: null, maxWon: null);
    double won(int inTok, int outTok) => (inTok * m.inputUsdPerMTok + outTok * m.outputUsdPerMTok) / 1e6 * 1400;
    // 짧게 와서 이어 쓰기를 2번 더 하면: 입력을 2번 더 보내고(앞에 쓴 글까지), 출력도 그만큼 더
    final extra = ClaudeChatClient.sceneMaxExtraCalls;
    return (
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      won: won(inputTokens, outputTokens),
      maxWon: won(inputTokens * (1 + extra) + outputTokens * extra, outputTokens * (1 + extra)),
    );
  }
}

final sceneRoomProvider =
    NotifierProvider.family<SceneRoomNotifier, SceneState, String>(SceneRoomNotifier.new);

/// 현실 장면 방에서 쓸 AI를 따로 고를 때 쓰는 방 이름 (톡 방과 따로: ai_room_<톡 방>@scene)
String sceneAiRoom(String sourceRoomId) => '$sourceRoomId@scene';

/// 현실 장면 방 주소 (톡 방 ID에서)
String sceneRoute(String sourceRoomId) => isFreeRoom(sourceRoomId)
    ? '/scene/${characterIdOfRoom(sourceRoomId)}?free=1'
    : '/scene/$sourceRoomId';
