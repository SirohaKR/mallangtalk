import 'dart:async';
import 'dart:math';
import 'package:flutter/widgets.dart' show Characters;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/claude_chat_client.dart';
import '../../core/storage/local_store.dart';
import '../../shared/models/mallangtalk_models.dart';
import '../auth/auth_state.dart';
import '../library/character_library.dart';
import '../settings/byok_settings.dart';
import '../settings/user_profile.dart';
import 'service_messages.dart';
import 'romance_settings.dart';
import '../../shared/utils/dialogue_input.dart';

/// 지금 시각 (테스트에서 특별 이벤트 시간을 바꿔 보려고 따로 둠)
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// 일상 대화 순서를 섞는 주사위 (테스트에서 순서를 고정하려고 따로 둠)
final storyRandomProvider = Provider<Random>((ref) => Random());

/// 공략 진행 상황 (대화방 하단에 '다시 하기' 버튼을 띄울지 판단하는 용도)
enum StoryProgress {
  playing, // 이벤트 진행 중
  stuck, // 남은 이벤트가 있지만 호감도·플래그 조건이 안 맞아 더 진행 불가
  cleared, // 공략 완료 (호감도 이벤트를 모두 끝내고 엔딩까지 봄. 사진 수와는 상관없음)
}

/// 공략 뒤 다시 볼 수 있는 대화: 아직 안 고른 선택지가 남은 대화
/// 다시 볼 수 있는 대화. [missed]: 그 시간에 없어서 아직 못 받은 특별한 톡
typedef ReplayableEvent = ({
  ScenarioEventModel event,
  int unseenChoices,
  bool missed
});

/// 공략 뒤 '못 받은 사진 모으기'의 한 줄: [choiceLabel]을 골랐다면 받을 수 있는 사진 [photos]장.
/// [choiceLabel]이 null이면 아직 안 나온(못 받은) 대화 전체
typedef MissedBranch = ({
  ScenarioEventModel event,
  String? choiceLabel,
  int photos
});

/// 공략 후 이야기 한 개의 상태: 봤음 / 다음에 올 차례 / 앞 이야기를 기다리는 중
enum EpilogueStatus { seen, next, waiting }

typedef EpilogueItem = ({
  ScenarioEventModel event,
  EpilogueStatus status,
  int photos
});

/// 대화방 이름: 스토리 방은 캐릭터 ID 그대로, 자유대화 방은 뒤에 #free
const _freeSuffix = '#free';
String freeRoomId(String characterId) => '$characterId$_freeSuffix';
bool isFreeRoom(String roomId) => roomId.endsWith(_freeSuffix);
String characterIdOfRoom(String roomId) => isFreeRoom(roomId)
    ? roomId.substring(0, roomId.length - _freeSuffix.length)
    : roomId;

/// [초보자 노트] 채팅방의 실시간 상태를 담는 클래스입니다.
/// 호감도 숫자(internalAffection)는 유저 화면에 절대 노출하지 않고 내부 분기 판정에만 사용합니다.
class ChatRoomState {
  final CharacterModel character;
  final int internalAffection; // 화면에는 숫자로 안 보여주고 내부에서만 계산!
  final String? currentEventId;
  final int currentStepOrder;
  final List<ChatMessageLog> messages;
  final List<ChoiceOption> currentChoices;
  final bool isCharacterTyping; // 상대방이 타자 치는 중('···')인지 여부
  final bool isByokAiModeEnabled; // 직접 입력(AI 자유대화) 모드 활성화 여부
  final String? previewPhotoLabel; // 채팅방 사진을 클릭했을 때 크게 보기 모달용
  final List<String> acquiredFlags;

  /// 이번 회차에 끝낸 이벤트 ID 목록
  final List<String> completedEventIds;

  /// 지금까지 수집한 컷씬의 이벤트 ID (앨범용, '다시 하기'를 해도 유지됨)
  final List<String> unlockedCutsceneEventIds;

  /// 앨범에 들어간 사진 설명 (사진 말풍선·컷씬 구분 없이, '다시 하기'를 해도 유지됨)
  final List<String> receivedPhotos;
  final StoryProgress progress;

  /// 내가 대화방에서 마지막으로 본 메시지 개수 (채팅방 목록의 안 읽은 숫자 계산용)
  final int seenMessageCount;

  /// 선택지를 고르면 입력창에 내 대사가 한 글자씩 쳐지는 중인 글 (보내면 비워짐)
  final String userDraft;

  /// 자유대화가 끝날 때마다 캐릭터가 남긴 한 줄 기억 (다음 자유대화 때 AI가 참고)
  final List<String> memories;

  /// 자유대화 AI 답장이 실패해서 '다시 보내기'를 띄울지
  final bool canRetryFreeTalk;

  /// 공략을 끝내고 스크립트(호감도·일상 대화·엔딩)를 다 봐서 자유대화가 열렸는지
  final bool freeTalkUnlocked;

  /// 방금 열려서 '스크립트를 전부 봤어요' 팝업을 띄울 차례인지
  final bool freeTalkJustUnlocked;

  /// 본 스크립트 수 / 전체 (잠겨 있을 때 안내용)
  final int scriptsSeen;
  final int scriptsTotal;

  /// 지금 선택지 중 예전 회차에 한 번도 안 고른 것 (공략을 한 번 끝낸 뒤 반짝이로 보여 줌)
  final List<String> sparkleChoiceIds;

  /// 공략 뒤 '안 본 갈래 다시 보기' 중인지 (진행·호감도에 영향 없음)
  final bool isReplaying;

  /// 대본(이벤트)이 재생 중인지. 말풍선 사이·대화 사이 잠깐 쉬는 동안에도 true라서
  /// 그 틈에 공략 완료 패널(다시 보기 버튼)이 깜빡 뜨지 않음
  final bool isScriptPlaying;

  const ChatRoomState({
    required this.character,
    required this.internalAffection,
    this.currentEventId,
    required this.currentStepOrder,
    required this.messages,
    required this.currentChoices,
    this.isCharacterTyping = false,
    this.isByokAiModeEnabled = false, // 기본은 선택지 모드, 자유대화는 유저가 직접 켬
    this.previewPhotoLabel,
    this.acquiredFlags = const [],
    this.completedEventIds = const [],
    this.unlockedCutsceneEventIds = const [],
    this.receivedPhotos = const [],
    this.progress = StoryProgress.playing,
    this.seenMessageCount = 0,
    this.userDraft = '',
    this.memories = const [],
    this.canRetryFreeTalk = false,
    this.freeTalkUnlocked = false,
    this.freeTalkJustUnlocked = false,
    this.scriptsSeen = 0,
    this.scriptsTotal = 0,
    this.sparkleChoiceIds = const [],
    this.isReplaying = false,
    this.isScriptPlaying = false,
  });

  /// 캐릭터가 보냈는데 내가 아직 안 본 말풍선 수
  int get unreadCount => messages
      .skip(seenMessageCount)
      .where((m) => !m.isUser && !m.isSystem)
      .length;

  /// 채팅방 목록에 보여줄 마지막 말풍선
  ChatMessageLog? get lastBubble {
    for (final m in messages.reversed) {
      if (!m.isSystem && !m.isHidden) return m;
    }
    return messages.where((m) => !m.isHidden).lastOrNull;
  }

  ChatRoomState copyWith({
    int? internalAffection,
    String? currentEventId,
    bool clearEvent = false,
    int? currentStepOrder,
    List<ChatMessageLog>? messages,
    List<ChoiceOption>? currentChoices,
    bool? isCharacterTyping,
    bool? isByokAiModeEnabled,
    String? previewPhotoLabel,
    bool clearPreviewPhoto = false,
    List<String>? acquiredFlags,
    List<String>? completedEventIds,
    List<String>? unlockedCutsceneEventIds,
    List<String>? receivedPhotos,
    StoryProgress? progress,
    int? seenMessageCount,
    String? userDraft,
    List<String>? memories,
    bool? canRetryFreeTalk,
    bool? freeTalkUnlocked,
    bool? freeTalkJustUnlocked,
    int? scriptsSeen,
    int? scriptsTotal,
    List<String>? sparkleChoiceIds,
    bool? isReplaying,
    bool? isScriptPlaying,
  }) {
    return ChatRoomState(
      character: character,
      internalAffection: internalAffection ?? this.internalAffection,
      currentEventId:
          clearEvent ? null : (currentEventId ?? this.currentEventId),
      currentStepOrder: currentStepOrder ?? this.currentStepOrder,
      messages: messages ?? this.messages,
      currentChoices: currentChoices ?? this.currentChoices,
      isCharacterTyping: isCharacterTyping ?? this.isCharacterTyping,
      isByokAiModeEnabled: isByokAiModeEnabled ?? this.isByokAiModeEnabled,
      previewPhotoLabel: clearPreviewPhoto
          ? null
          : (previewPhotoLabel ?? this.previewPhotoLabel),
      acquiredFlags: acquiredFlags ?? this.acquiredFlags,
      completedEventIds: completedEventIds ?? this.completedEventIds,
      unlockedCutsceneEventIds:
          unlockedCutsceneEventIds ?? this.unlockedCutsceneEventIds,
      receivedPhotos: receivedPhotos ?? this.receivedPhotos,
      progress: progress ?? this.progress,
      seenMessageCount: seenMessageCount ?? this.seenMessageCount,
      userDraft: userDraft ?? this.userDraft,
      memories: memories ?? this.memories,
      canRetryFreeTalk: canRetryFreeTalk ?? this.canRetryFreeTalk,
      freeTalkUnlocked: freeTalkUnlocked ?? this.freeTalkUnlocked,
      freeTalkJustUnlocked: freeTalkJustUnlocked ?? this.freeTalkJustUnlocked,
      scriptsSeen: scriptsSeen ?? this.scriptsSeen,
      scriptsTotal: scriptsTotal ?? this.scriptsTotal,
      sparkleChoiceIds: sparkleChoiceIds ?? this.sparkleChoiceIds,
      isReplaying: isReplaying ?? this.isReplaying,
      isScriptPlaying: isScriptPlaying ?? this.isScriptPlaying,
    );
  }
}

/// [초보자 노트] 리얼한 카톡 대화 템포를 만드는 핵심 Notifier입니다!
/// 1. 괄호 지문이나 (+호감도), (실시간 AI 응답) 같은 어색한 문구를 완전히 없앴습니다.
/// 2. 글자 수와 감정(speedFactor)에 따라 짧은 말은 툭툭 빠르게, 긴 말이나 망설이는 말은 느리게 끊어 칩니다.
/// 3. 내가 단문으로 여러 번 연속해서 톡을 보낼 때(또는 입력창에 타자를 치고 있는 동안)는
///    캐릭터가 중간에 끼어들지 않고 내가 말을 다 끝낼 때까지 기다렸다가 한꺼번에 '1'이 사라지며 답장합니다!
/// 4. 이벤트 하나가 끝나면 호감도·플래그 조건을 보고 다음 이벤트로 넘어가고,
///    지정된 단계에서 컷씬(CG)을 띄우며, 조건을 다 채우면 엔딩과 함께 공략 완료를 알립니다.
class ChatRoomNotifier extends FamilyNotifier<ChatRoomState, String> {
  late ScenarioBundle _bundle;
  late LocalStore _store;
  final _random = Random();

  /// 내가 연속으로 톡을 보낼 때 상대방 답장을 보류하는 디바운스 타이머
  Timer? _userBurstReplyTimer;

  /// 내가 지금 입력창에 글자를 치고 있는지 여부
  bool _isUserCurrentlyTypingText = false;

  /// 지금까지 끝까지 본 스크립트(호감도 이벤트·일상 대화·엔딩) ID. 회차가 바뀌어도 남음
  final Set<String> _seenScripts = {};

  /// AI 답장을 기다리는 중인지 (그동안 더 보내면 요청을 겹쳐 보내지 않고 답이 온 뒤 합쳐서 다시)
  bool _awaitingAiReply = false;

  /// 내가 연속으로 보낸 메시지들을 모아두는 버퍼
  final List<String> _pendingUserBurstTexts = [];

  /// '다시 하기'를 누르면 숫자가 바뀌어서, 이전 회차에서 아직 돌던 연출을 멈추게 함
  int _runId = 0;

  /// 이번 자유대화에서 캐릭터가 답한 횟수 (이야기 진행 중이면 [freeTalkWrapUpTurn]부터 마무리, [freeTalkMaxTurns]에서 끝)
  int _freeTurns = 0;
  static const freeTalkWrapUpTurn = 6;
  static const freeTalkMaxTurns = 12;

  /// 지금 이벤트를 시작할 때의 호감도·플래그 (자유대화로 미룬 이벤트를 다음에 처음부터 다시 하려고)
  ({int affection, List<String> flags})? _eventStart;

  /// 지금까지 모든 회차에서 한 번이라도 고른 선택지 ID
  final Set<String> _chosen = {};

  /// 다시 보기 전 진행 상태 (끝나면 그대로 돌려놓음)
  ({
    int affection,
    List<String> flags,
    List<String> completed
  })? _replaySnapshot;

  /// 지금 돌고 있는 대본 재생 수 (겹쳐서 돌 수 있어 숫자로 셈)
  int _scriptDepth = 0;

  /// 대본 재생 하나를 감싸서, 도는 동안 [ChatRoomState.isScriptPlaying]을 켜 둠
  Future<void> _playing(Future<void> Function() body) async {
    _scriptDepth++;
    if (!_disposed && !state.isScriptPlaying)
      state = state.copyWith(isScriptPlaying: true);
    try {
      await body();
    } finally {
      if (_scriptDepth > 0) _scriptDepth--;
      if (_scriptDepth == 0 && !_disposed && state.isScriptPlaying)
        state = state.copyWith(isScriptPlaying: false);
    }
  }

  /// '처음부터 다시'를 누른 시각 (ms). 같은 회차 안에서 다른 기기가 옛 상태로 덮어쓰지 않게 구분
  int? _resetAt;
  bool _disposed = false;
  ScriptNodeModel? _currentNode;
  int _currentNextBubble = 0;

  /// 이 대화방이 자유대화 방인지 (스토리 방과 따로, 호감도·이야기 없이 AI와만 대화)
  late bool _free;
  late String _characterId;

  /// 서비스 말랑이 대화방인지 (정해진 때 먼저 톡, 호감도·이야기 없음)
  bool _service = false;
  Timer? _serviceTimer;
  bool _delivering = false;

  /// 이야기 없이 AI와만 주고받는 방 (자유대화 방·서비스 말랑이)
  bool get _aiRoom => _free || _service;

  /// 진행 기록을 저장하는 이름 (스토리 방은 캐릭터 ID, 자유대화 방은 ID#free)
  String get _roomId => _free ? freeRoomId(_characterId) : _characterId;

  @override
  ChatRoomState build(String roomId) {
    _disposed = false;
    _scriptDepth = 0;
    _currentNode = null;
    _currentNextBubble = 0;
    // 로그인 계정이 바뀌거나 로그아웃하면 대화방 상태도 즉시 폐기·초기화되어 이전 계정 데이터가 남지 않게 함
    ref.watch(authProvider.select((a) => a.user?.username));
    _store = ref.watch(localStoreProvider);
    _free = isFreeRoom(roomId);
    final characterId = _characterId = characterIdOfRoom(roomId);
    ref.onDispose(() {
      _disposed = true;
      _userBurstReplyTimer?.cancel();
      _serviceTimer?.cancel();
      _runId++; // 대화방이 닫히면(캐릭터 삭제·로그아웃 등) 돌던 연출을 멈춤
    });

    // 캐릭터 존재 여부만 감시하여, 로그아웃 중이거나 아직 목록이 안 불러와졌을 때 오류 없이 대기하다가 생기면 다시 그림
    ref.watch(characterLibraryProvider
        .select((list) => list.any((e) => e.id == characterId)));
    final bundle = ref.read(characterBundleProvider(characterId));
    if (bundle == null) {
      _disposed = true;
      return ChatRoomState(
        character: CharacterModel(
          id: characterId,
          creatorId: '',
          name: '',
          statusMessage: '',
          avatarUrl: '',
          worldviewPrompt: '',
          affectionStages: const [],
        ),
        internalAffection: 0,
        currentStepOrder: 0,
        messages: const [],
        currentChoices: const [],
      );
    }
    _bundle = bundle;
    _service = !_free && bundle.character.isService;
    final album = _store.loadAlbum(characterId);
    if (_service) {
      // 서비스 말랑이: 정해진 때가 지났으면 그동안 온 톡을 쌓아 두고, 방이 살아 있는 동안 30초마다 확인
      final savedService = _store.loadRun(roomId);
      final svcMsgs = savedService?.messages ?? const [];
      final svcSeen = (savedService?.seenMessageCount ?? svcMsgs.length)
          .clamp(0, svcMsgs.length);
      _serviceTimer?.cancel();
      _serviceTimer =
          Timer.periodic(const Duration(seconds: 30), (_) => _deliverService());
      Future.microtask(_deliverService);
      return _freshRunState(unlockedCutscenes: album).copyWith(
        isByokAiModeEnabled: true,
        internalAffection: 100,
        messages: svcMsgs,
        seenMessageCount: svcSeen,
        memories: savedService?.memories ?? const [],
      );
    }
    if (_free) {
      // 자유대화 방: 이야기는 진행하지 않고, 지난 대화와 한 줄 기억만 이어서
      final savedFree = _store.loadRun(roomId);
      final freeMsgs = savedFree?.messages ?? const [];
      final freeSeen = (savedFree?.seenMessageCount ?? freeMsgs.length)
          .clamp(0, freeMsgs.length);
      return _freshRunState(unlockedCutscenes: album).copyWith(
        isByokAiModeEnabled: true,
        messages: freeMsgs,
        seenMessageCount: freeSeen,
        memories: savedFree?.memories ?? const [],
      );
    }
    final saved = _store.loadRun(characterId);
    _chosen
      ..clear()
      ..addAll(_store.loadChosenChoices(characterId));
    _replaySnapshot = null;
    _restoreReceivedPhotos(album, saved?.messages ?? const []);
    _seenScripts
      ..clear()
      ..addAll(_store.loadSeenEvents(characterId))
      // 이 기능 전에 진행한 기록도 인정
      ..addAll(saved?.completedEventIds ?? const [])
      ..addAll([
        if (saved?.cleared ?? false)
          for (final e in bundle.events)
            if (e.isEnding) e.id,
      ]);

    _resetAt = saved?.resetAt;
    // 저장된 진행 기록이 있으면 마지막으로 끝낸 이벤트 다음부터 이어서 진행
    if (saved != null) {
      final savedSeen = (saved.seenMessageCount ?? saved.messages.length)
          .clamp(0, saved.messages.length);
      final restored = _freshRunState(unlockedCutscenes: album).copyWith(
        internalAffection: saved.affection,
        acquiredFlags: saved.flags,
        completedEventIds: saved.completedEventIds,
        messages: saved.messages,
        progress: saved.cleared ? StoryProgress.cleared : null,
        seenMessageCount: savedSeen,
        memories: saved.memories,
      );
      final runId = _runId;
      final node = saved.nodeId != null ? _bundle.nodes[saved.nodeId] : null;
      if (node != null && _eventById(node.eventId) != null) {
        _currentNode = node;
        _currentNextBubble = saved.nextBubble;
        // 이벤트 중간에 나갔으면 나가기 전 그 자리부터 (치던 말풍선 다음, 또는 선택지)
        Future.microtask(() => _playing(() =>
            _playNode(node, runId, from: saved.nextBubble, resuming: true)));
        return restored.copyWith(
            currentEventId: node.eventId,
            currentStepOrder: node.stepOrder,
            isScriptPlaying: true);
      }
      if (!saved.cleared) {
        Future.microtask(() => _advance(runId));
      } else {
        // 공략을 끝낸 뒤에도 특별한 시간에 들어오면 그 시간 톡은 옴. 그다음 못 본 일상 대화
        Future.microtask(() => _playing(() async {
              await _playSpecialIfDue(runId);
              if (runId == _runId && state.currentChoices.isEmpty)
                await _continueEpilogue(runId);
            }));
      }
      // 들어오자마자 패널이 한 번 깜빡이지 않게, 이어질 대본이 있는지 보기 전까지는 재생 중으로 둠
      return saved.cleared ? restored.copyWith(isScriptPlaying: true) : restored;
    }
    // 처음 대화하는 캐릭터는 내 별명을 정한 뒤(begin)부터 대화가 시작됨
    if (ref.read(chatPrefsProvider(characterId)).nickname != null) {
      _started = true;
      final runId = _runId;
      Future.microtask(() => _advance(runId));
    }
    return _freshRunState(unlockedCutscenes: album);
  }

  ChatRoomState _freshRunState({required List<String> unlockedCutscenes}) {
    return ChatRoomState(
      character: _bundle.character,
      internalAffection: 0,
      currentStepOrder: 0,
      messages: const [],
      currentChoices: const [],
      unlockedCutsceneEventIds: unlockedCutscenes,
      receivedPhotos: _store.loadReceivedPhotos(_bundle.character.id),
      freeTalkUnlocked: _store.freeTalkUnlocked(_bundle.character.id),
      scriptsSeen: _scriptIds.where(_seenScripts.contains).length,
      scriptsTotal: _scriptIds.length,
    );
  }

  /// 자유대화를 열려면 다 봐야 하는 스크립트 (특별한 시간 톡은 시간이 맞아야 와서 빼요)
  List<String> get _scriptIds => [
        for (final e in _bundle.events)
          if (e.isAffectionEvent || e.isDaily || e.isEnding) e.id,
      ];

  void _markSeen(ScenarioEventModel event) {
    if (_disposed) return;
    if (!(event.isAffectionEvent ||
        event.isDaily ||
        event.isEnding ||
        event.isAfterEnding)) return;
    if (!_seenScripts.add(event.id)) return;
    _store.saveSeenEvents(_bundle.character.id, _seenScripts.toList());
    state = state.copyWith(
        scriptsSeen: _scriptIds.where(_seenScripts.contains).length);
  }

  /// 공략을 끝낸 뒤: 공략 후 이야기를 순서대로, 그다음 아직 한 번도 못 본 일상 대화를 이어서 보여 줌
  Future<void> _continueEpilogue(int runId) =>
      _playing(() => _continueEpilogueInner(runId));

  Future<void> _continueEpilogueInner(int runId) async {
    if (state.progress != StoryProgress.cleared) return;
    final after = _bundle.events
        .where((e) =>
            e.isAfterEnding &&
            e.followsEventId == null &&
            !state.completedEventIds.contains(e.id) &&
            e.requiredFlags.every(state.acquiredFlags.contains))
        .toList()
      ..sort((a, b) => a.chapterOrder.compareTo(b.chapterOrder));
    final next = after.firstOrNull ??
        _bundle.events
            .where((e) => e.isDaily && !_seenScripts.contains(e.id))
            .firstOrNull;
    if (next == null) return;
    await Future.delayed(const Duration(milliseconds: 1500));
    if (runId != _runId) return;
    await _playEvent(next, runId);
  }

  /// '스크립트를 전부 봤어요' 팝업을 닫음
  void ackFreeTalkUnlocked() =>
      state = state.copyWith(freeTalkJustUnlocked: false);

  bool _started = false;

  /// 별명을 정하고 대화방에 처음 들어올 때 대화 시작 (이미 시작했으면 아무 일 없음)
  void begin() {
    if (_aiRoom || _started || state.messages.isNotEmpty) return;
    _started = true;
    _advance(_runId);
  }

  /// 처음부터 다시 플레이 (수집한 컷씬은 그대로 남김)
  void restart() {
    _runId++;
    _userBurstReplyTimer?.cancel();
    _pendingUserBurstTexts.clear();
    _freeTurns = 0;
    if (_aiRoom) {
      // 자유대화 방·서비스 말랑이는 대화만 비움 (한 줄 기억은 남김)
      state = state.copyWith(
          messages: const [],
          seenMessageCount: 0,
          isCharacterTyping: false,
          canRetryFreeTalk: false);
      _saveRun();
      return;
    }
    _replaySnapshot = null;
    _resetAt = DateTime.now().millisecondsSinceEpoch;
    state = _freshRunState(unlockedCutscenes: state.unlockedCutsceneEventIds)
        .copyWith(memories: state.memories);
    _saveRun(cleared: false);
    _started = true;
    _advance(_runId);
  }

  /// 진행 기록을 브라우저에 저장. 이벤트 경계마다, 그리고 이벤트 중간에는 말풍선마다
  /// [node]·[nextBubble]로 돌아올 자리를 함께 저장해서 나갔다 와도 그 자리부터 이어짐
  void _saveRun(
      {bool? cleared,
      ScriptNodeModel? node,
      int nextBubble = 0,
      bool keepCurrentNode = false}) {
    if (_disposed) return;
    cleared ??= state.progress == StoryProgress.cleared;
    // 다시 보기 중에는 원래 진행 상태로 저장 (나갔다 오면 다시 보기는 접힘)
    final snap = _replaySnapshot;
    if (snap != null) {
      node = null;
    } else if (keepCurrentNode) {
      node = _currentNode;
      nextBubble = _currentNextBubble;
    } else {
      _currentNode = node;
      _currentNextBubble = nextBubble;
    }
    _store.saveRun(
      _roomId,
      SavedRun(
        affection: snap?.affection ?? state.internalAffection,
        flags: snap?.flags ?? state.acquiredFlags,
        completedEventIds: snap?.completed ?? state.completedEventIds,
        messages: state.messages,
        cleared: cleared,
        eventId: node?.eventId,
        nodeId: node?.id,
        nextBubble: nextBubble,
        memories: state.memories,
        resetAt: _resetAt,
        seenMessageCount:
            state.seenMessageCount.clamp(0, state.messages.length),
      ),
    );
  }

  /// 아직 안 끝낸 호감도 이벤트 중, 조건(호감도·플래그)을 만족하는 가장 앞 챕터의 이벤트
  ScenarioEventModel? _nextPlayableEvent() {
    for (final event in _bundle.events) {
      if (!event.isAffectionEvent) continue;
      if (state.completedEventIds.contains(event.id)) continue;
      if (_isUnlocked(event)) return event;
    }
    return null;
  }

  /// 지금 호감도 단계에서 나올 수 있는, 이번 회차에 아직 안 본 일상 대화
  /// 여러 개면 무작위로 하나 (이어지는 대화로 붙여 둔 건 앞 대화 뒤에만 나와서 빼요)
  ScenarioEventModel? _nextDailyTalk() {
    final candidates = [
      for (final event in _bundle.events)
        if (event.isDaily &&
            event.followsEventId == null &&
            !state.completedEventIds.contains(event.id) &&
            _isUnlocked(event))
          event,
    ];
    if (candidates.isEmpty) return null;
    return candidates[ref.read(storyRandomProvider).nextInt(candidates.length)];
  }

  bool _isUnlocked(ScenarioEventModel event) {
    final range = _bundle.affectionRangeOf(event);
    final score = state.internalAffection;
    return score >= range.min &&
        (range.max == null || score <= range.max!) &&
        event.requiredFlags.every(state.acquiredFlags.contains);
  }

  /// 지금 실제 시각에 열려 있고 아직 한 번도 못 본 특별 이벤트
  ScenarioEventModel? _dueSpecialEvent() {
    if (state.completedEventIds.isEmpty) return null; // 첫 대화는 늘 첫 이벤트부터
    final seen = _store.loadSeenSpecials(_bundle.character.id);
    final now = ref.read(clockProvider)();
    for (final event in _bundle.events) {
      if (!event.isSpecial || seen.contains(event.id)) continue;
      if (event.realTime == null || !event.realTime!.contains(now)) continue;
      if (_isUnlocked(event)) return event;
    }
    return null;
  }

  /// 공략 완료 후 등 대화가 멈춰 있을 때 특별 이벤트 시간이면 재생
  Future<void> _playSpecialIfDue(int runId) async {
    if (runId != _runId || state.currentChoices.isNotEmpty) return;
    final special = _dueSpecialEvent();
    if (special != null) await _playEvent(special, runId);
  }

  /// 대화방에 들어올 때: 이야기가 멈춰 있는 상태(공략 완료·막힘)면 특별 이벤트 시간인지 확인
  void checkSpecialEvents() {
    if (_aiRoom) return;
    if (state.isCharacterTyping || state.currentChoices.isNotEmpty) return;
    if (state.progress == StoryProgress.playing || _scriptDepth > 0) return;
    _playing(() => _playSpecialIfDue(_runId));
  }

  /// 방금 끝낸 게 호감도 이벤트였는지 (그 다음엔 일상 대화를 하나 끼워 넣음)
  bool get _justFinishedStoryEvent {
    final lastId = state.completedEventIds.lastOrNull;
    if (lastId == null) return false;
    return _eventById(lastId)?.isAffectionEvent ?? false;
  }

  /// 시간이 지나는 장면 사이의 텀: 앞 대화가 끝난 뒤 시간 표시까지, 시간 표시 뒤 첫 톡까지
  static const sceneGapBefore = Duration(seconds: 4);
  static const sceneGapAfter = Duration(milliseconds: 2500);
  DateTime? _lastEventEndedAt;

  Future<void> _playEvent(ScenarioEventModel event, int runId) =>
      _playing(() => _playEventInner(event, runId));

  Future<void> _playEventInner(ScenarioEventModel event, int runId) async {
    _eventStart =
        (affection: state.internalAffection, flags: state.acquiredFlags);
    state = state.copyWith(currentEventId: event.id);
    final firstNode = _bundle.firstNodeOf(event.id);
    if (event.timeNotice != null) {
      // '다음 날'처럼 시간이 지나는 장면: 앞 대화가 끝나고 조금 쉬었다가 시간 표시, 또 잠깐 뒤에 첫 톡
      // (대화 속도 설정을 따르고, 대화방에 막 들어왔을 때는 바로 시간 표시)
      final tempo = ref.read(chatPrefsProvider(_characterId)).tempo;
      if (_lastEventEndedAt case final ended?) {
        final wait = sceneGapBefore * tempo - DateTime.now().difference(ended);
        if (wait > Duration.zero) await Future.delayed(wait);
        if (runId != _runId) return;
      }
      _addSystemNotice(event.timeNotice!);
      // Persist the new scene and its notice before waiting for the first bubble.
      // Otherwise markSeen can save the notice without a resume node and replay it.
      _saveRun(node: firstNode);
      await Future.delayed(Duration(
          milliseconds: (sceneGapAfter.inMilliseconds * tempo).round()));
      if (runId != _runId) return;
    }
    if (firstNode == null) {
      await _finishEvent(event, runId);
      return;
    }
    _saveRun(node: firstNode);
    await _playNode(firstNode, runId);
  }

  /// 노드 하나의 캐릭터 대사를 재생하고, 선택지를 띄우거나(선택지가 없으면) 이벤트를 끝냅니다.
  /// [from]: 나갔다 들어왔을 때 이미 친 말풍선은 건너뜀
  Future<void> _playNode(ScriptNodeModel node, int runId,
      {int from = 0, bool resuming = false}) async {
    var typedAny = false;
    if (from == 0 && node.userFirst.isNotEmpty) {
      // 선톡: 내가 먼저 입력칸에 쳐서 보냄
      for (var i = 0; i < node.userFirst.length; i++) {
        if (!await _sendUserBubble(node.userFirst[i], i, () => runId == _runId))
          return;
        typedAny = true;
      }
      if (node.characterBubbles.firstOrNull?.delaySeconds == 0) {
        await Future.delayed(const Duration(milliseconds: 700));
        if (runId != _runId) return;
        _markAllUserMessagesRead();
      }
    }
    for (var i = from; i < node.characterBubbles.length; i++) {
      if (!await _typeOut(node.characterBubbles[i], () => runId == _runId))
        return;
      typedAny = true;
      if (i < node.characterBubbles.length - 1)
        _saveRun(node: node, nextBubble: i + 1);
    }

    state = state.copyWith(currentStepOrder: node.stepOrder);

    // 제작자가 컷씬을 둔 장면(단계)의 대사까지 보면 그 장면(CG)이 앨범에 모임 (대화는 멈추지 않음)
    // 다른 갈래로 가서 못 받은 사진은 공략 뒤 '안 본 갈래 다시 보기'나 다음 회차에 모을 수 있어요 (엔딩과는 상관없음)
    final event = _eventById(node.eventId);
    final trigger = event?.cutsceneTriggerStep;
    if (event != null && trigger != null && node.stepOrder == trigger) {
      _collectCutscene(event);
    }

    if (node.choices.isEmpty) {
      if (event != null) await _finishEvent(event, runId);
      return;
    }
    state = state.copyWith(
      currentChoices: node.choices,
      sparkleChoiceIds: [
        if (_clearedOnce)
          for (final c in node.choices)
            if (!_chosen.contains(c.id)) c.id,
      ],
    );
    if (!resuming || typedAny) {
      _saveRun(node: node, nextBubble: node.characterBubbles.length);
    }
  }

  void _collectCutscene(ScenarioEventModel event) {
    if (_disposed) return;
    if (state.unlockedCutsceneEventIds.contains(event.id)) return;
    state = state.copyWith(
      unlockedCutsceneEventIds: [...state.unlockedCutsceneEventIds, event.id],
    );
    _store.saveAlbum(_bundle.character.id, state.unlockedCutsceneEventIds);
    _receivePhoto(event.cutscenePhotoTitle);
  }

  /// 사진 말풍선·컷씬을 받으면 앨범에 넣음
  void _receivePhoto(String? label) {
    if (_disposed) return;
    final key = label?.trim() ?? '';
    if (key.isEmpty || state.receivedPhotos.contains(key)) return;
    state = state.copyWith(receivedPhotos: [...state.receivedPhotos, key]);
    _store.saveReceivedPhotos(_bundle.character.id, state.receivedPhotos);
  }

  /// 앨범을 사진 전체로 바꾸기 전 기록도 인정: 모은 컷씬 + 대화에서 받은 사진
  void _restoreReceivedPhotos(
      List<String> cutsceneIds, List<ChatMessageLog> messages) {
    final id = _bundle.character.id;
    final received = {..._store.loadReceivedPhotos(id)};
    final before = received.length;
    for (final e in _bundle.events) {
      final title = e.cutscenePhotoTitle?.trim() ?? '';
      if (cutsceneIds.contains(e.id) && title.isNotEmpty) received.add(title);
    }
    for (final m in messages) {
      if (!m.isUser && m.hasPhoto) received.add(m.photoLabel!.trim());
    }
    if (received.length != before)
      _store.saveReceivedPhotos(id, received.toList());
  }

  /// 이벤트 하나를 끝내고 다음 이벤트로 넘어가거나, 공략 완료/막힘을 판정합니다.
  Future<void> _finishEvent(ScenarioEventModel event, int runId) async {
    _lastEventEndedAt = DateTime.now();
    if (event.isSpecial) {
      final id = _bundle.character.id;
      _store.saveSeenSpecials(
          id, {..._store.loadSeenSpecials(id), event.id}.toList());
      if (_replaySnapshot != null) {
        _endReplay();
        return;
      }
      if (state.progress != StoryProgress.playing)
        return; // 공략 완료·막힘 뒤에 온 톡이면 여기서 끝
      await Future.delayed(const Duration(milliseconds: 1200));
      if (runId != _runId) return;
      await _advance(runId);
      return;
    }
    _markSeen(event);
    if (_replaySnapshot != null) {
      _endReplay();
      return;
    }
    if (event.isEnding) {
      _addSystemNotice('${state.character.name} 공략 완료');
      state = state.copyWith(progress: StoryProgress.cleared);
      _saveRun(cleared: true);
      await _continueEpilogue(runId);
      return;
    }

    state = state.copyWith(
      completedEventIds: {...state.completedEventIds, event.id}.toList(),
    );
    _saveRun();
    // 이어지는 대화가 붙어 있으면 바로 이어서
    final followUp = _followUpOf(event);
    if (followUp != null) {
      await Future.delayed(const Duration(milliseconds: 1200));
      if (runId != _runId) return;
      await _playEvent(followUp, runId);
      return;
    }
    if (state.progress == StoryProgress.cleared) {
      await _continueEpilogue(runId); // 엔딩 뒤 남은 일상 대화
      return;
    }
    await Future.delayed(const Duration(milliseconds: 1200));
    if (runId != _runId) return;
    await _advance(runId);
  }

  /// 다시 보기 끝: 진행 상태를 그대로 돌려놓음 (받은 사진·고른 선택지만 남음)
  void _endReplay() {
    final snap = _replaySnapshot;
    if (snap == null) return;
    _replaySnapshot = null;
    state = state.copyWith(
      internalAffection: snap.affection,
      acquiredFlags: snap.flags,
      completedEventIds: snap.completed,
      isReplaying: false,
      clearEvent: true,
    );
    _addSystemNotice('다시 보기가 끝났어요');
    _saveRun();
  }

  /// 다음에 열 수 있는 이벤트를 재생하거나, 더 없으면 공략 완료/놓친 컷씬/막힘을 판정합니다.
  /// 순서: 호감도 이벤트가 끝나면 지금 단계의 일상 대화 하나 → 다음 호감도 이벤트.
  /// 다음 이벤트 조건이 안 맞으면 남은 일상 대화로 호감도를 더 쌓을 기회를 줍니다.
  Future<void> _advance(int runId) async {
    if (state.isByokAiModeEnabled) return; // 자유대화 중에는 이야기를 멈춤 (끝나면 이어짐)
    // 실제 시간에 맞춰 오는 특별한 톡이 있으면 먼저
    final special = _dueSpecialEvent();
    if (special != null) {
      await _playEvent(special, runId);
      return;
    }

    if (_justFinishedStoryEvent) {
      final daily = _nextDailyTalk();
      if (daily != null) {
        await _playEvent(daily, runId);
        return;
      }
    }

    final next = _nextPlayableEvent();
    if (next != null) {
      await _playEvent(next, runId);
      return;
    }

    final extraDaily = _nextDailyTalk();
    if (extraDaily != null) {
      await _playEvent(extraDaily, runId);
      return;
    }

    final remaining = _bundle.events.where(
        (e) => e.isAffectionEvent && !state.completedEventIds.contains(e.id));
    if (remaining.isNotEmpty) {
      _addSystemNotice('${state.character.name}의 연락이 끊겼어요');
      state = state.copyWith(progress: StoryProgress.stuck);
      return;
    }

    // 호감도 이벤트를 모두 끝내면 엔딩 (사진을 다 못 모아도 나옴)
    final ending = _bundle.events.where((e) => e.isEnding).firstOrNull;
    if (ending != null) {
      await _playEvent(ending, runId);
    } else {
      _addSystemNotice('${state.character.name} 공략 완료');
      state = state.copyWith(progress: StoryProgress.cleared);
      _saveRun(cleared: true);
      await _continueEpilogue(runId);
    }
  }

  /// 서비스 말랑이: '한 번 더 뽑기' (지금 바로 새 문구 한 통)
  Future<void> rerollService() => _deliverService(reroll: true);

  /// 서비스 말랑이: 보낼 때가 된 톡을 보냄. 처음 대화방이 생기면 바로 한 통,
  /// 앱을 안 연 동안 지난 시각들은 그 시각으로 쌓아 둠 (AI 모드는 가장 최근 한 통만)
  Future<void> _deliverService({bool reroll = false}) async {
    final config = _bundle.character.service;
    if (!_service || config == null || _delivering) return;
    _delivering = true;
    final runId = _runId;
    try {
      final saved = _store.loadServiceState(_characterId);
      final now = ref.read(clockProvider)();
      final used = {...saved.used};
      var slots = reroll || saved.last == null
          ? [now]
          : dueServiceSlots(config, saved.last!, now);
      if (slots.isEmpty) return;
      if (config.mode == 'ai') slots = [slots.last];
      for (final slot in slots) {
        final text = await _composeService(config, slot, used, loud: reroll);
        if (runId != _runId) return;
        if (text == null) break;
        if (reroll) {
          if (!await _typeOut(
              ScriptBubblePiece(text: text), () => runId == _runId)) return;
        } else {
          state = state.copyWith(messages: [
            ...state.messages,
            ChatMessageLog(
              id: 'svc_${slot.millisecondsSinceEpoch}_${_random.nextInt(1 << 20)}',
              isUser: false,
              speakerCharacterId: state.character.id,
              speakerName: state.character.name,
              text: text,
              timestamp: slot,
            ),
          ]);
        }
      }
      await _store.saveServiceState(_characterId, now, used.toList());
      _saveRun();
    } finally {
      _delivering = false;
    }
  }

  /// 문구 하나 만들기 (목록·표는 바로, AI는 내 AI 키로). 못 만들면 null
  Future<String?> _composeService(
      ServiceConfig config, DateTime when, Set<String> used,
      {bool loud = false}) async {
    if (config.mode == 'ai') {
      final byok = ref.read(roomByokProvider(_roomId));
      if (!byok.canUseAi) {
        if (loud)
          _addSystemNotice('AI 키를 넣으면 ${state.character.name}의 톡을 AI가 새로 써요');
        return null;
      }
      try {
        return await ref.read(claudeChatClientProvider).serviceMessage(
              provider: byok.provider,
              apiKey: byok.apiKey ?? '',
              relay: byok.relay,
              model: byok.model,
              character: state.character,
              prompt: config.aiPrompt,
              userName: _nickname,
              userInfo: serviceUserInfoLine(ref.read(serviceUserInfoProvider(_characterId))),
              now: when,
            );
      } on ClaudeChatException catch (e) {
        if (loud) _addSystemNotice(e.message);
        return null;
      }
    }
    final count = config.mode == 'table'
        ? config.rows.length
        : config.lines.where((l) => l.trim().isNotEmpty).length;
    if (config.noRepeat && count > 0 && used.length >= count)
      used.clear(); // 한 바퀴 다 돌았으면 처음부터
    final msg = composeServiceMessage(
      config,
      userName: _nickname,
      charName: state.character.name,
      now: when,
      random: ref.read(storyRandomProvider),
      used: used,
      userInfo: ref.read(serviceUserInfoProvider(_characterId)),
    );
    if (msg == null) return null;
    used.add(msg.key);
    return msg.text;
  }

  /// 이 대화 바로 뒤에 붙은 '이어지는 대화' (이번 회차에 아직 안 봤고 조건이 맞는 것)
  ScenarioEventModel? _followUpOf(ScenarioEventModel event) => _bundle.events
      .where((e) =>
          e.followsEventId == event.id &&
          !e.isSpecial &&
          !state.completedEventIds.contains(e.id) &&
          e.requiredFlags.every(state.acquiredFlags.contains))
      .firstOrNull;

  /// 한 번이라도 공략을 끝낸 적이 있는지 (그 뒤로는 안 고른 선택지에 반짝이)
  bool get _clearedOnce =>
      state.progress == StoryProgress.cleared ||
      _bundle.events.any((e) => e.isEnding && _seenScripts.contains(e.id));

  /// 앨범에 아직 안 들어간 사진 수
  int get missedPhotoCount {
    final received = state.receivedPhotos.toSet();
    return _bundle.albumPhotos.where((p) => !received.contains(p.label)).length;
  }

  /// 공략 뒤 다시 볼 수 있는 대화 (안 고른 선택지가 남은 것, 이야기 순서대로)
  /// 특별한 시간 톡은 그 시간에 없어서 못 받은 것도 여기서 볼 수 있어요 (이야기 뒤에 붙음)
  List<ReplayableEvent> get replayableEvents {
    if (_aiRoom) return const [];
    final out = <ReplayableEvent>[];
    final specials = <ReplayableEvent>[];
    final seenSpecials = _store.loadSeenSpecials(_bundle.character.id).toSet();
    final events = [..._bundle.events]
      ..sort((a, b) => a.chapterOrder.compareTo(b.chapterOrder));
    for (final e in events) {
      final missed = e.isSpecial && !seenSpecials.contains(e.id);
      if (!e.isSpecial && !_seenScripts.contains(e.id)) continue;
      final unseen = _bundle.nodes.values
          .where((n) => n.eventId == e.id)
          .expand((n) => n.choices)
          .where((c) => !_chosen.contains(c.id))
          .length;
      if (unseen == 0 && !missed) continue;
      (e.isSpecial ? specials : out)
          .add((event: e, unseenChoices: unseen, missed: missed));
    }
    return [...out, ...specials];
  }

  /// 공략 뒤 '못 받은 사진 모으기' 목록: 안 고른 선택지마다 그쪽으로 가면 받을 수 있는 (아직 없는) 사진 수.
  /// 아직 안 나온 일상 대화·못 받은 특별한 톡은 대화 전체로 셈. 공략 후 이야기는 [epilogueItems]에서 따로
  List<MissedBranch> get missedBranches {
    if (_aiRoom) return const [];
    final received = state.receivedPhotos.toSet();
    final seenSpecials = _store.loadSeenSpecials(_bundle.character.id).toSet();
    final out = <MissedBranch>[];
    final events = [..._bundle.events]
      ..sort((a, b) => a.chapterOrder.compareTo(b.chapterOrder));
    for (final e in events) {
      if (e.isAfterEnding) continue;
      final unseenWhole = e.isSpecial
          ? !seenSpecials.contains(e.id)
          : e.isDaily && !_seenScripts.contains(e.id);
      if (unseenWhole) {
        final n = _photosFrom(e, _bundle.firstNodeOf(e.id), received);
        if (n > 0) out.add((event: e, choiceLabel: null, photos: n));
        continue;
      }
      if (!e.isSpecial && !_seenScripts.contains(e.id)) continue;
      final nodes = _bundle.nodes.values.where((n) => n.eventId == e.id).toList()
        ..sort((a, b) => a.stepOrder.compareTo(b.stepOrder));
      for (final node in nodes) {
        for (final c in node.choices) {
          if (_chosen.contains(c.id)) continue;
          final next = c.nextNodeId == null ? null : _bundle.nodes[c.nextNodeId];
          final n = _photosFrom(e, next, received);
          if (n > 0) out.add((event: e, choiceLabel: c.buttonLabel, photos: n));
        }
      }
    }
    return out;
  }

  /// [start] 노드부터 이 대화 끝까지 갈 수 있는 길에 나오는, 아직 안 받은 사진 수 (사진 말풍선 + 컷씬)
  int _photosFrom(ScenarioEventModel event, ScriptNodeModel? start, Set<String> received) {
    final found = <String>{};
    final visited = <String>{};
    final queue = [if (start != null) start];
    while (queue.isNotEmpty) {
      final node = queue.removeLast();
      if (!visited.add(node.id)) continue;
      for (final b in node.characterBubbles) {
        if (b.hasPhoto) found.add(b.photoLabel!.trim());
      }
      if (event.cutsceneTriggerStep == node.stepOrder) {
        final t = event.cutscenePhotoTitle?.trim() ?? '';
        if (t.isNotEmpty) found.add(t);
      }
      for (final c in node.choices) {
        final next = c.nextNodeId == null ? null : _bundle.nodes[c.nextNodeId];
        if (next != null) queue.add(next);
      }
    }
    return found.where((p) => p.isNotEmpty && !received.contains(p)).length;
  }

  /// 공략 후 이야기 목록 (이야기 순서대로): 본 것, 다음에 올 것, 그 뒤를 기다리는 것
  List<EpilogueItem> get epilogueItems {
    if (_aiRoom) return const [];
    final received = state.receivedPhotos.toSet();
    final events = _bundle.events.where((e) => e.isAfterEnding).toList()
      ..sort((a, b) => a.chapterOrder.compareTo(b.chapterOrder));
    var nextGiven = false;
    return [
      for (final e in events)
        (
          event: e,
          status: _seenScripts.contains(e.id) || state.completedEventIds.contains(e.id)
              ? EpilogueStatus.seen
              : !nextGiven &&
                      state.progress == StoryProgress.cleared &&
                      (e.followsEventId == null || state.completedEventIds.contains(e.followsEventId)) &&
                      e.requiredFlags.every(state.acquiredFlags.contains) &&
                      (nextGiven = true)
                  ? EpilogueStatus.next
                  : EpilogueStatus.waiting,
          photos: _photosFrom(e, _bundle.firstNodeOf(e.id), received),
        ),
    ];
  }

  /// 공략 뒤 아직 안 본 공략 후 이야기를 지금 받기 (대화가 멈춰 있을 때만)
  Future<void> playNextEpilogue() async {
    if (state.progress != StoryProgress.cleared ||
        state.isCharacterTyping ||
        state.currentChoices.isNotEmpty ||
        _scriptDepth > 0 ||
        _replaySnapshot != null) return;
    final next = epilogueItems.where((i) => i.status == EpilogueStatus.next).firstOrNull;
    if (next == null) return;
    await _playEvent(next.event, _runId);
  }

  /// 공략 뒤 '안 본 갈래 다시 보기': 대화를 처음부터 다시 보되 호감도·진행은 끝나면 그대로 돌려놓음.
  /// 안 고른 선택지는 반짝이로 보여서, 놓친 사진을 모을 수 있어요
  Future<void> replayEvent(String eventId) async {
    final event = _eventById(eventId);
    if (_free || event == null || state.progress != StoryProgress.cleared)
      return;
    if (state.isCharacterTyping ||
        state.currentChoices.isNotEmpty ||
        _scriptDepth > 0 ||
        _replaySnapshot != null) return;
    _replaySnapshot = (
      affection: state.internalAffection,
      flags: state.acquiredFlags,
      completed: state.completedEventIds,
    );
    state = state.copyWith(isReplaying: true);
    _addSystemNotice('다시 보기: ${event.title} (진행에는 영향 없어요)');
    await _playEvent(event, _runId);
  }

  ScenarioEventModel? _eventById(String id) =>
      _bundle.events.where((e) => e.id == id).firstOrNull;

  void _addSystemNotice(String text) {
    final notice = ChatMessageLog(
      id: 'system_${DateTime.now().microsecondsSinceEpoch}_${state.messages.length}',
      isUser: false,
      isSystem: true,
      speakerCharacterId: 'system',
      speakerName: '',
      text: text,
      timestamp: DateTime.now(),
    );
    state = state.copyWith(messages: [...state.messages, notice]);
  }

  /// 캐릭터 타자 속도 × 설정의 대화 속도
  double get _pace =>
      state.character.typingSpeedMultiplier *
      ref.read(chatPrefsProvider(_characterId)).tempo;

  /// 이 대화에서 불리는 내 별명
  String get _nickname => ref.read(chatNicknameProvider(_characterId));

  /// ±15% 정도 들쭉날쭉하게 (매번 똑같은 박자면 기계 같아서)
  double _jitter() => 0.85 + _random.nextDouble() * 0.3;

  /// [초보자 노트] 말풍선 하나를 사람처럼 쳐서 보냅니다.
  /// 1. 읽고 나서 뭐라고 할지 잠깐 멈칫 (입력 중 표시 없음)
  /// 2. '입력 중' 표시: 휴대폰으로 한 글자에 0.15초 정도 + 말투(speedFactor)와 캐릭터 타자 속도 반영
  /// 3. 망설이는 말(speedFactor 1.3 이상)은 치다가 멈췄다가(썼다 지웠다) 다시 침
  /// 중간에 회차가 바뀌거나 내가 끼어들면 false를 돌려주고 멈춥니다.
  Future<bool> _typeOut(
      ScriptBubblePiece bubble, bool Function() stillValid) async {
    final pace = _pace;
    if (bubble.delaySeconds > 0) {
      // 답장이 늦게 오는 연출: 그동안 내 톡의 '1'은 그대로 (대화 속도 설정을 따르고 최대 30초)
      final tempo = ref.read(chatPrefsProvider(_characterId)).tempo;
      await Future.delayed(Duration(
          milliseconds:
              (bubble.delaySeconds.clamp(1, 30) * 1000 * tempo).round()));
      if (!stillValid()) return false;
      _markAllUserMessagesRead();
    }
    await Future.delayed(
        Duration(milliseconds: (500 * pace * _jitter()).round()));
    if (!stillValid()) return false;

    final chars = Characters(CharacterModel.fillUserName(bubble.text, _nickname,
            charName: state.character.name))
        .length;
    final typingMs =
        ((700 + chars * 150) * bubble.speedFactor * pace * _jitter())
            .clamp(450 * pace, 9000 * pace)
            .round();

    state = state.copyWith(isCharacterTyping: true);
    if (bubble.speedFactor >= 1.3 && typingMs > 1500 * pace) {
      // 썼다 지웠다: 40% 치고 → 잠깐 멈춤 → 나머지
      await Future.delayed(Duration(milliseconds: (typingMs * 0.4).round()));
      if (!stillValid()) return false;
      state = state.copyWith(isCharacterTyping: false);
      await Future.delayed(
          Duration(milliseconds: (900 * pace * _jitter()).round()));
      if (!stillValid()) return false;
      state = state.copyWith(isCharacterTyping: true);
      await Future.delayed(Duration(milliseconds: (typingMs * 0.6).round()));
    } else {
      await Future.delayed(Duration(milliseconds: typingMs));
    }
    if (!stillValid()) {
      state = state.copyWith(isCharacterTyping: false);
      return false;
    }

    final reply = ChatMessageLog(
      id: 'char_${DateTime.now().microsecondsSinceEpoch}_${state.messages.length}',
      isUser: false,
      speakerCharacterId: state.character.id,
      speakerName: state.character.name,
      text: CharacterModel.fillUserName(bubble.text, _nickname,
          charName: state.character.name),
      photoLabel: bubble.photoLabel,
      photoImage: bubble.photoImage,
      timestamp: _free ? ref.read(clockProvider)() : DateTime.now(),
    );
    state = state.copyWith(
      isCharacterTyping: false,
      messages: [...state.messages, reply],
    );
    if (reply.hasPhoto) _receivePhoto(reply.photoLabel);
    return true;
  }

  /// 대화방을 보고 있을 때 호출 → 안 읽은 숫자 0 (저장소에도 기록해 새로고침해도 유지)
  void markSeen() {
    if (state.seenMessageCount == state.messages.length) return;
    state = state.copyWith(seenMessageCount: state.messages.length);
    _saveRun(keepCurrentNode: true);
  }

  /// 모든 내 안 읽음('1') 말풍선을 일괄 '읽음' 처리합니다.
  void _markAllUserMessagesRead() {
    final updated = state.messages
        .map((m) => (m.isUser && m.isUnread) ? m.copyWith(isUnread: false) : m)
        .toList();
    state = state.copyWith(messages: updated);
  }

  /// 내 대사를 입력창에 사람이 치듯 한 글자씩 채움 (대화 속도 설정을 따름)
  /// 중간에 회차가 바뀌면 입력창을 비우고 false
  Future<bool> _typeUserDraft(
      String text, bool first, bool Function() stillValid) async {
    final tempo = ref.read(chatPrefsProvider(_characterId)).tempo;
    await Future.delayed(Duration(
        milliseconds: ((first ? 350 : 450) * tempo * _jitter()).round()));
    if (!stillValid()) return false;
    final chars = Characters(text).toList();
    // 긴 대사도 3초 안쪽으로 끝나게 한 번에 치는 글자 수를 늘림
    final step = (chars.length / 30).ceil().clamp(1, 10);
    for (var n = step; n < chars.length + step; n += step) {
      state = state.copyWith(userDraft: chars.take(n).join());
      await Future.delayed(
          Duration(milliseconds: (85 * tempo * _jitter()).round()));
      if (!stillValid()) {
        state = state.copyWith(userDraft: '');
        return false;
      }
    }
    // 다 치고 전송 누르기 전 잠깐
    await Future.delayed(Duration(milliseconds: (250 * tempo).round()));
    if (!stillValid()) {
      state = state.copyWith(userDraft: '');
      return false;
    }
    return true;
  }

  /// 내 말풍선 하나를 입력칸에 쳐서 보냄 (처음엔 '1' 표시)
  Future<bool> _sendUserBubble(
      ScriptBubblePiece piece, int index, bool Function() stillValid) async {
    final text = CharacterModel.fillUserName(piece.text, _nickname,
        charName: state.character.name);
    if (!piece.hasPhoto &&
        (text.trim().isEmpty ||
            isUnspokenAction(text) ||
            stageDirectionOf(text) != null)) return stillValid();
    if (!await _typeUserDraft(text, index == 0, stillValid)) return false;
    final myMsg = ChatMessageLog(
      id: 'user_choice_${DateTime.now().microsecondsSinceEpoch}_${state.messages.length}_$index',
      isUser: true,
      speakerCharacterId: 'user',
      speakerName: _nickname,
      text: text,
      photoLabel: piece.photoLabel,
      photoImage: piece.photoImage,
      isUnread: true,
      timestamp: DateTime.now(),
    );
    state = state.copyWith(userDraft: '', messages: [...state.messages, myMsg]);
    return true;
  }

  /// [선택지 클릭 시] 내가 고른 대답도 짧게 끊어서 연속 전송한 뒤, 캐릭터가 현실적인 타자 속도로 답장합니다.
  Future<void> selectChoice(ChoiceOption choice) =>
      _playing(() => _selectChoice(choice));

  Future<void> _selectChoice(ChoiceOption choice) async {
    final runId = _runId;
    _userBurstReplyTimer?.cancel();
    if (_chosen.add(choice.id))
      _store.saveChosenChoices(_bundle.character.id, _chosen.toList());
    state = state.copyWith(
      currentChoices: const [],
      sparkleChoiceIds: const [],
      internalAffection:
          (state.internalAffection + choice.affectionDelta).clamp(0, 100),
      acquiredFlags: [
        ...state.acquiredFlags,
        if (choice.addFlag != null) choice.addFlag!,
      ],
    );

    // 1. 내 말풍선마다 입력창에 한 글자씩 쳐서 보냄 (처음엔 '1' 표시)
    for (int i = 0; i < choice.userBubbles.length; i++) {
      if (!await _sendUserBubble(
          choice.userBubbles[i], i, () => runId == _runId)) return;
    }

    // 2. 내가 연속 전송을 마친 뒤 0.7초 후 캐릭터가 읽음('1' 일괄 사라짐)
    //    다음 말풍선이 늦게 오는 답장이면 그때까지 '1'이 남음
    final nextNode =
        choice.nextNodeId != null ? _bundle.nodes[choice.nextNodeId] : null;
    final lateReply = nextNode != null &&
        nextNode.userFirst.isEmpty &&
        (nextNode.characterBubbles.firstOrNull?.delaySeconds ?? 0) > 0;
    if (!lateReply) {
      await Future.delayed(const Duration(milliseconds: 700));
      if (runId != _runId) return;
      _markAllUserMessagesRead();
    }

    // 3. 다음 노드가 있으면 이어서 재생, 없으면 이 이벤트는 끝
    if (nextNode != null) {
      _saveRun(node: nextNode);
      await _playNode(nextNode, runId);
      return;
    }
    final event =
        state.currentEventId != null ? _eventById(state.currentEventId!) : null;
    if (event != null) await _finishEvent(event, runId);
  }

  /// [핵심! 유저 연속 톡 보호] 유저가 입력창에 글자를 치고 있는 동안에는
  /// 캐릭터가 중간에 답장하지 않고 기다리도록 타이머를 연장합니다.
  void onUserTypingChanged(String currentInputText) {
    _isUserCurrentlyTypingText = currentInputText.trim().isNotEmpty;
    if (_pendingUserBurstTexts.isNotEmpty) {
      _scheduleBurstReply();
    }
  }

  /// [유저 자유 입력 & 사진 찍어 올리기]
  /// 내가 짧게 여러 번 연속으로 보내도 그 동안에는 캐릭터가 답장하지 않고 기다립니다!
  bool sendUserMessage(
      {required String text,
      String? photoLabel,
      String? photoImage,
      ChatMessageLog? replyTo}) {
    if (_disposed) return false;
    final trimmed = text.trim();
    if (trimmed.isEmpty && (photoLabel == null || photoLabel.isEmpty))
      return false;
    if (!ref.read(roomByokProvider(_roomId)).canUseAi) {
      _addSystemNotice('자유대화를 하려면 API 키를 등록해 주세요.');
      return false;
    }

    final now = ref.read(clockProvider)();
    final lastMessage = state.messages.where((m) => !m.isSystem).lastOrNull;
    // 실패한 요청의 재시도나 아직 생성 중인 답장을 새 장면으로 나누지 않는다.
    if (_free &&
        lastMessage != null &&
        !state.messages.last.isConversationBreak &&
        _pendingUserBurstTexts.isEmpty &&
        !_awaitingAiReply &&
        !state.isCharacterTyping &&
        now.difference(lastMessage.timestamp) >= const Duration(minutes: 10)) {
      final divider = ChatMessageLog(
        id: 'conversation_break_${now.microsecondsSinceEpoch}',
        isUser: false,
        isSystem: true,
        isConversationBreak: true,
        speakerCharacterId: 'system',
        speakerName: '',
        text: '새로운 대화',
        timestamp: now,
      );
      state = state.copyWith(messages: [...state.messages, divider]);
    }

    final myMsg = ChatMessageLog(
      id: 'user_burst_${DateTime.now().microsecondsSinceEpoch}_${state.messages.length}',
      isUser: true,
      speakerCharacterId: 'user',
      speakerName: _nickname,
      text: trimmed.isEmpty ? '사진을 보냈습니다.' : trimmed,
      photoLabel: photoLabel,
      photoImage: photoImage,
      replyToId: replyTo?.id,
      replyToText: replyTo?.text,
      replyToName: replyTo?.speakerName,
      isHidden: isUnspokenAction(trimmed) && photoLabel == null,
      isUnread: true, // 내가 연속으로 보내는 동안에는 계속 '1'이 유지됨!
      timestamp: now,
    );

    _pendingUserBurstTexts.add(
      '${replyTo == null ? '' : '[답장 대상: ${replyTo.speakerName}: ${replyTo.text}] '}${photoLabel != null ? '[사진 전송: $photoLabel] ${dialogueInputForAi(trimmed)}' : dialogueInputForAi(trimmed)}',
    );
    _isUserCurrentlyTypingText = false;

    state = state.copyWith(messages: [...state.messages, myMsg]);
    _saveRun(keepCurrentNode: true);

    // 내가 추가로 더 칠 수 있으므로 대기 타이머를 새로고침합니다.
    _scheduleBurstReply();
    return true;
  }

  /// End only the current free-chat scene; keep history and relationship memory.
  void endConversation() {
    if (!_free ||
        _disposed ||
        state.messages.lastOrNull?.isConversationBreak == true) return;
    _userBurstReplyTimer?.cancel();
    _pendingUserBurstTexts.clear();
    _isUserCurrentlyTypingText = false;
    _runId++;
    final now = ref.read(clockProvider)();
    state = state
        .copyWith(isCharacterTyping: false, canRetryFreeTalk: false, messages: [
      ...state.messages,
      ChatMessageLog(
          id: 'manual_break_${DateTime.now().microsecondsSinceEpoch}',
          isUser: false,
          isSystem: true,
          isConversationBreak: true,
          speakerCharacterId: 'system',
          speakerName: '',
          text: '대화 끝',
          timestamp: now),
    ]);
    _saveRun();
  }

  /// 내가 마지막 톡을 보내고 2.2초 동안 추가 입력이 없을 때만 캐릭터가 읽고 답장을 시작합니다.
  void _scheduleBurstReply() {
    _userBurstReplyTimer?.cancel();
    _userBurstReplyTimer = Timer(const Duration(milliseconds: 2200), () {
      // 만약 유저가 아직 입력창에 다음 문장을 치고 있는 중이면 답장하지 않고 더 기다림!
      // AI 답을 기다리는 중이면 그 답이 오면 새로 보낸 말까지 합쳐서 다시 물어봄 (요청이 겹치지 않게)
      if (_awaitingAiReply) return;
      if (_isUserCurrentlyTypingText) {
        _scheduleBurstReply();
        return;
      }
      _processCombinedUserBurstReply();
    });
  }

  /// 내가 연속으로 보낸 여러 마디를 한꺼번에 읽고('1' 제거), 현실적으로 끊어서 답장합니다.
  Future<void> _processCombinedUserBurstReply() async {
    if (_pendingUserBurstTexts.isEmpty) return;
    if (!ref.read(roomByokProvider(_roomId)).canUseAi) {
      state = state.copyWith(isCharacterTyping: false, canRetryFreeTalk: true);
      _addSystemNotice('자유대화를 하려면 API 키를 등록해 주세요.');
      return;
    }

    final combinedInput = List<String>.from(_pendingUserBurstTexts);
    _pendingUserBurstTexts.clear();
    final runId = _runId;
    bool stillValid() => runId == _runId && state.isByokAiModeEnabled;

    // 스토리 방에서 이야기 진행 중이면 정해진 만큼 주고받은 뒤 캐릭터가 마무리 (자유대화 방·공략 뒤에는 끝없이)
    final limited = !_aiRoom && _storyWaiting;
    _freeTurns++;
    final pace = limited
        ? FreeTalkPace(
            turn: _freeTurns,
            wrapUp: _freeTurns >= freeTalkWrapUpTurn,
            mustEnd: _freeTurns >= freeTalkMaxTurns,
          )
        : FreeTalkPace.open;

    // AI에게 보낼 '지금까지 대화'는 방금 보낸 톡('1'이 남은 것)을 뺀 기록
    final historyBeforeBurst =
        state.messages.where((m) => !m.isUnread).toList();

    // 1. 내가 보낸 연속 톡들의 '1'이 한꺼번에 사라짐
    final burstIds = {
      for (final m in state.messages)
        if (m.isUser && m.isUnread) m.id
    };
    state = state.copyWith(canRetryFreeTalk: false);
    _markAllUserMessagesRead();
    await Future.delayed(const Duration(milliseconds: 350));

    // 2. 설정된 AI로 답장을 요청. 키가 없을 때 예시 답장을 만들지 않는다.
    final List<ScriptBubblePiece> replyPieces;
    var affectionDelta = 0;
    var ends = false;
    var memory = '';
    final byok = ref.read(roomByokProvider(_roomId));
    if (byok.canUseAi) {
      state = state.copyWith(isCharacterTyping: true);
      _awaitingAiReply = true;
      try {
        final reply = await ref.read(claudeChatClientProvider).reply(
              provider: byok.provider,
              apiKey: byok.apiKey ?? '',
              relay: byok.relay,
              model: byok.model,
              character: state.character,
              stageLabel: _aiRoom ? null : _currentStageLabel(),
              userName: _nickname,
              userIntro: ref.read(userProfileProvider).intro,
              userPersona: [
                ref.read(chatPersonaProvider(_characterId)),
                if (_free)
                  romanceDirection(
                      ref.read(romanceSettingsProvider(_characterId)),
                      state.character),
              ].where((s) => s.isNotEmpty).join('\n\n'),
              currentEventTitle: state.currentEventId != null
                  ? _eventById(state.currentEventId!)?.title
                  : null,
              history: [
                ...historyBeforeBurst,
                ...state.messages.where(
                    (m) => burstIds.contains(m.id) && m.photoImage != null)
              ],
              newUserMessages: combinedInput,
              pace: pace,
              memories: state.memories,
              photos: _free ? _bundle.freeTalkPhotos : const [],
              // 무료 한도(429)·붐빔(503)으로 기다렸다 다시 물어볼 때, 입력 중 점만 계속 보이지 않게 알려 줌
              onRetryWait: (wait) {
                if (stillValid())
                  _addSystemNotice(
                      'AI가 지금 붐벼서 ${wait.inSeconds}초 뒤에 다시 물어볼게요. (무료 등급은 1분에 보낼 수 있는 횟수가 정해져 있어요)');
              },
            );
        _awaitingAiReply = false;
        if (!stillValid()) return;
        if (_pendingUserBurstTexts.isNotEmpty) {
          // 답을 기다리는 동안 더 보냈으면 이 답은 버리고, 이번 말까지 한꺼번에 다시 물어봄
          _requeueBurst(combinedInput, burstIds);
          _scheduleBurstReply();
          return;
        }
        // 자유대화 방에서 AI가 고른 사진은 말풍선 뒤에 사진으로 보냄 (앨범에도 들어감)
        final photo = _free
            ? _bundle.freeTalkPhotos
                .where((p) => p.id == reply.photoId)
                .firstOrNull
            : null;
        replyPieces = [
          for (final text in reply.bubbles) ScriptBubblePiece(text: text),
          if (photo != null)
            ScriptBubblePiece(
                text: '', photoLabel: photo.label, photoImage: photo.ref),
        ];
        affectionDelta =
            _aiRoom ? 0 : reply.affectionDelta; // 자유대화 방·서비스 말랑이는 호감도 없음
        ends = limited && (reply.ends || pace.mustEnd);
        memory = reply.memory;
      } on ClaudeChatException catch (e) {
        _awaitingAiReply = false;
        if (!stillValid()) return;
        // 못 읽은 걸로 되돌려 두고('1' 다시 표시) '다시 보내기'를 누르거나 더 보내면 같이 다시 물어봄
        final sentMore = _pendingUserBurstTexts.isNotEmpty;
        _requeueBurst(combinedInput, burstIds);
        if (sentMore) {
          _scheduleBurstReply(); // 더 보낸 말과 같이 곧 다시 물어보니 오류는 안 띄움
          return;
        }
        state = state.copyWith(canRetryFreeTalk: true);
        _addSystemNotice(e.message);
        return;
      } finally {
        _awaitingAiReply = false;
        if (runId != _runId && _pendingUserBurstTexts.isNotEmpty)
          _scheduleBurstReply();
      }
    } else {
      _requeueBurst(combinedInput, burstIds);
      _addSystemNotice('자유대화를 하려면 API 키를 등록해 주세요.');
      return;
    }

    state = state.copyWith(isCharacterTyping: false);
    for (final piece in replyPieces) {
      // 만약 캐릭터가 답장하는 도중에 내가 또 새로운 톡을 쳤다면 즉시 중단하고 내 말을 먼저 받음!
      // (마무리 인사는 끝까지 보냄)
      final sent = await _typeOut(piece,
          () => stillValid() && (ends || _pendingUserBurstTexts.isEmpty));
      if (!sent) return;
    }

    // AI가 판정한 호감도 변화는 답장을 다 보낸 뒤 반영 (화면에는 숫자로 안 보임)
    if (affectionDelta != 0) {
      state = state.copyWith(
        internalAffection:
            (state.internalAffection + affectionDelta).clamp(0, 100),
      );
    }
    if (memory.isNotEmpty) {
      final all = [...state.memories, memory];
      state =
          state.copyWith(memories: all.skip(max(0, all.length - 5)).toList());
    }
    if (ends) {
      await _endFreeTalk(byCharacter: true);
    } else {
      _saveRun();
    }
  }

  /// 답을 못 받은 내 톡들을 다시 '안 읽음'으로 돌리고, 다음에 물어볼 말 맨 앞에 되돌려 둠
  void _requeueBurst(List<String> texts, Set<String> ids) {
    _freeTurns--;
    _pendingUserBurstTexts.insertAll(0, texts);
    state = state.copyWith(
      isCharacterTyping: false,
      messages: [
        for (final m in state.messages)
          ids.contains(m.id) ? m.copyWith(isUnread: true) : m,
      ],
    );
  }

  /// AI 답장이 실패했을 때 '다시 보내기'
  void retryFreeTalk() {
    if (!state.canRetryFreeTalk || !state.isByokAiModeEnabled) return;
    _userBurstReplyTimer?.cancel();
    _processCombinedUserBurstReply();
  }

  /// 이야기가 아직 진행 중(또는 조건이 안 맞아 멈춤)이라 자유대화를 끝내고 돌아가야 하는지
  bool get _storyWaiting =>
      state.progress == StoryProgress.playing ||
      state.progress == StoryProgress.stuck;

  /// 지금 하던 도중인 이벤트 (끝났거나 없으면 null)
  ScenarioEventModel? get _eventInProgress {
    final id = state.currentEventId;
    final event = id == null ? null : _eventById(id);
    if (event == null || !_storyWaiting) return null;
    if (event.isSpecial)
      return _store.loadSeenSpecials(_bundle.character.id).contains(event.id)
          ? null
          : event;
    return state.completedEventIds.contains(event.id) ? null : event;
  }

  /// 자유대화를 켜면 하던 이벤트를 멈춤: 선택지는 사라지고,
  /// 호감도 이벤트(엔딩 포함)는 미뤘다가 끝난 뒤 처음부터, 일상·특별 톡은 지나간 걸로
  void _suspendStory() {
    final event = _eventInProgress;
    _runId++;
    var next = state.copyWith(
      currentChoices: const [],
      isCharacterTyping: false,
      userDraft: '',
      clearEvent: true,
    );
    if (event != null) {
      if (event.isDaily) {
        next = next.copyWith(
            completedEventIds: {...next.completedEventIds, event.id}.toList());
      } else if (event.isSpecial) {
        final id = _bundle.character.id;
        _store.saveSeenSpecials(
            id, {..._store.loadSeenSpecials(id), event.id}.toList());
      } else if (_eventStart case final start?) {
        // 미룬 이벤트에서 이미 고른 선택지 점수는 되돌림 (다시 할 때 또 오르지 않게)
        next = next.copyWith(
            internalAffection: start.affection, acquiredFlags: start.flags);
      }
    }
    state = next;
    if (event != null && !event.isDaily && !event.isSpecial) {
      _addSystemNotice('하던 이야기는 자유대화가 끝나면 이어져요');
    }
    _saveRun();
  }

  /// 자유대화를 끝내고 멈췄던 이야기로 돌아감 ([byCharacter]: 캐릭터가 마무리 인사를 하고 끝냄)
  Future<void> _endFreeTalk({required bool byCharacter}) async {
    _freeTurns = 0;
    _userBurstReplyTimer?.cancel();
    _pendingUserBurstTexts.clear();
    _isUserCurrentlyTypingText = false;
    final runId = ++_runId;
    state = state.copyWith(
        isByokAiModeEnabled: false,
        isCharacterTyping: false,
        canRetryFreeTalk: false);
    if (byCharacter) _addSystemNotice('자유대화가 끝났어요');
    _saveRun();
    if (state.progress == StoryProgress.stuck) {
      // 자유대화로 호감도가 올라 다음 이야기가 열렸으면 다시 진행
      if (_nextPlayableEvent() == null && _nextDailyTalk() == null) return;
      state = state.copyWith(progress: StoryProgress.playing);
    }
    if (state.progress != StoryProgress.playing) return;
    await Future.delayed(const Duration(milliseconds: 1500));
    if (runId != _runId) return;
    await _advance(runId);
  }

  String _currentStageLabel() {
    for (final stage in state.character.affectionStages) {
      if (state.internalAffection >= stage.minScore &&
          state.internalAffection <= stage.maxScore) {
        return stage.stageLabel;
      }
    }
    return state.character.affectionStages.lastOrNull?.stageLabel ?? '친구';
  }

  /// 자유대화 켜기·끄기. 이야기 도중에 켜면 하던 이벤트를 멈춤.
  void toggleDirectInputMode(bool enabled) {
    if (_aiRoom || enabled == state.isByokAiModeEnabled) return;
    if (enabled && !state.freeTalkUnlocked) return;
    if (!enabled) {
      _endFreeTalk(byCharacter: false);
      return;
    }
    _freeTurns = 0;
    if (_storyWaiting) _suspendStory();
    state = state.copyWith(isByokAiModeEnabled: true);
  }

  void openPhotoPreview(String photoLabel) {
    state = state.copyWith(previewPhotoLabel: photoLabel);
  }

  void closePhotoPreview() {
    state = state.copyWith(clearPreviewPhoto: true);
  }
}

/// 캐릭터마다 대화방 하나씩 (캐릭터 ID로 구분)
final chatRoomProvider =
    NotifierProvider.family<ChatRoomNotifier, ChatRoomState, String>(
  ChatRoomNotifier.new,
);
