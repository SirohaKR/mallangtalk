import 'dart:async';
import 'dart:math';
import 'package:flutter/widgets.dart' show Characters;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/claude_chat_client.dart';
import '../../core/storage/local_store.dart';
import '../../shared/models/mallangtalk_models.dart';
import '../library/character_library.dart';
import '../settings/byok_settings.dart';
import '../settings/user_profile.dart';

/// 지금 시각 (테스트에서 특별 이벤트 시간을 바꿔 보려고 따로 둠)
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// 공략 진행 상황 (대화방 하단에 '다시 하기' 버튼을 띄울지 판단하는 용도)
enum StoryProgress {
  playing, // 이벤트 진행 중
  missedCutscenes, // 이벤트는 다 끝냈는데 못 본 컷씬이 남음 → 다시 하기로 수집
  stuck, // 남은 이벤트가 있지만 호감도·플래그 조건이 안 맞아 더 진행 불가
  cleared, // 공략 완료 (모든 컷씬 수집 + 모든 호감도 이벤트 완료)
}

/// [초보자 노트] 채팅방의 실시간 상태를 담는 클래스입니다.
/// 호감도 숫자(internalAffection)는 유저 화면에 절대 노출하지 않고 내부 분기 판정에만 사용합니다.
class ChatRoomState {
  final CharacterModel character;
  final int internalAffection; // 화면에는 숫자로 안 보여주고 내부에서만 계산!
  final String? currentEventId;
  final int currentStepOrder;
  final List<ChatMessageLog> messages;
  final List<ChoiceOption> currentChoices;
  final bool isCharacterTyping;   // 상대방이 타자 치는 중('···')인지 여부
  final bool isByokAiModeEnabled; // 직접 입력(AI 자유대화) 모드 활성화 여부
  final String? previewPhotoLabel; // 채팅방 사진을 클릭했을 때 크게 보기 모달용
  final List<String> acquiredFlags;
  /// 이번 회차에 끝낸 이벤트 ID 목록
  final List<String> completedEventIds;
  /// 지금까지 수집한 컷씬의 이벤트 ID (앨범용, '다시 하기'를 해도 유지됨)
  final List<String> unlockedCutsceneEventIds;
  final StoryProgress progress;
  /// 내가 대화방에서 마지막으로 본 메시지 개수 (채팅방 목록의 안 읽은 숫자 계산용)
  final int seenMessageCount;
  /// 선택지를 고르면 입력창에 내 대사가 한 글자씩 쳐지는 중인 글 (보내면 비워짐)
  final String userDraft;

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
    this.progress = StoryProgress.playing,
    this.seenMessageCount = 0,
    this.userDraft = '',
  });

  /// 캐릭터가 보냈는데 내가 아직 안 본 말풍선 수
  int get unreadCount => messages
      .skip(seenMessageCount)
      .where((m) => !m.isUser && !m.isSystem)
      .length;

  /// 채팅방 목록에 보여줄 마지막 말풍선
  ChatMessageLog? get lastBubble {
    for (final m in messages.reversed) {
      if (!m.isSystem) return m;
    }
    return messages.lastOrNull;
  }

  ChatRoomState copyWith({
    int? internalAffection,
    String? currentEventId,
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
    StoryProgress? progress,
    int? seenMessageCount,
    String? userDraft,
  }) {
    return ChatRoomState(
      character: character,
      internalAffection: internalAffection ?? this.internalAffection,
      currentEventId: currentEventId ?? this.currentEventId,
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
      progress: progress ?? this.progress,
      seenMessageCount: seenMessageCount ?? this.seenMessageCount,
      userDraft: userDraft ?? this.userDraft,
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
  /// 내가 연속으로 보낸 메시지들을 모아두는 버퍼
  final List<String> _pendingUserBurstTexts = [];
  /// '다시 하기'를 누르면 숫자가 바뀌어서, 이전 회차에서 아직 돌던 연출을 멈추게 함
  int _runId = 0;

  @override
  ChatRoomState build(String characterId) {
    ref.onDispose(() {
      _userBurstReplyTimer?.cancel();
      _runId++; // 대화방이 닫히면(캐릭터 삭제 등) 돌던 연출을 멈춤
    });

    // 캐릭터 목록이 바뀔 때마다 대화가 처음부터 다시 시작되지 않도록 watch 대신 read
    final bundle = ref.read(characterBundleProvider(characterId));
    if (bundle == null) {
      throw StateError('캐릭터를 찾을 수 없어요: $characterId');
    }
    _bundle = bundle;
    _store = ref.watch(localStoreProvider);
    final album = _store.loadAlbum(characterId);
    final saved = _store.loadRun(characterId);

    // 저장된 진행 기록이 있으면 마지막으로 끝낸 이벤트 다음부터 이어서 진행
    if (saved != null) {
      final restored = _freshRunState(unlockedCutscenes: album).copyWith(
        internalAffection: saved.affection,
        acquiredFlags: saved.flags,
        completedEventIds: saved.completedEventIds,
        messages: saved.messages,
        progress: saved.cleared ? StoryProgress.cleared : null,
        seenMessageCount: saved.messages.length,
      );
      final runId = _runId;
      final node = saved.nodeId != null ? _bundle.nodes[saved.nodeId] : null;
      if (!saved.cleared && node != null && _eventById(node.eventId) != null) {
        // 이벤트 중간에 나갔으면 나가기 전 그 자리부터 (치던 말풍선 다음, 또는 선택지)
        Future.microtask(() => _playNode(node, runId, from: saved.nextBubble));
        return restored.copyWith(currentEventId: node.eventId, currentStepOrder: node.stepOrder);
      }
      if (!saved.cleared) {
        Future.microtask(() => _advance(runId));
      } else {
        // 공략을 끝낸 뒤에도 특별한 시간에 들어오면 그 시간 톡은 옴
        Future.microtask(() => _playSpecialIfDue(runId));
      }
      return restored;
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
    );
  }

  bool _started = false;

  /// 별명을 정하고 대화방에 처음 들어올 때 대화 시작 (이미 시작했으면 아무 일 없음)
  void begin() {
    if (_started || state.messages.isNotEmpty) return;
    _started = true;
    _advance(_runId);
  }

  /// 처음부터 다시 플레이 (수집한 컷씬은 그대로 남김)
  void restart() {
    _runId++;
    _userBurstReplyTimer?.cancel();
    _pendingUserBurstTexts.clear();
    state = _freshRunState(unlockedCutscenes: state.unlockedCutsceneEventIds)
        .copyWith(isByokAiModeEnabled: state.isByokAiModeEnabled);
    _store.clearRun(_bundle.character.id);
    _started = true;
    _advance(_runId);
  }

  /// 진행 기록을 브라우저에 저장. 이벤트 경계마다, 그리고 이벤트 중간에는 말풍선마다
  /// [node]·[nextBubble]로 돌아올 자리를 함께 저장해서 나갔다 와도 그 자리부터 이어짐
  void _saveRun({bool cleared = false, ScriptNodeModel? node, int nextBubble = 0}) {
    _store.saveRun(
      _bundle.character.id,
      SavedRun(
        affection: state.internalAffection,
        flags: state.acquiredFlags,
        completedEventIds: state.completedEventIds,
        messages: state.messages,
        cleared: cleared,
        eventId: node?.eventId,
        nodeId: node?.id,
        nextBubble: nextBubble,
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
  ScenarioEventModel? _nextDailyTalk() {
    for (final event in _bundle.events) {
      if (!event.isDaily) continue;
      if (state.completedEventIds.contains(event.id)) continue;
      if (_isUnlocked(event)) return event;
    }
    return null;
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
    if (state.isCharacterTyping || state.currentChoices.isNotEmpty) return;
    if (state.progress == StoryProgress.playing) return;
    _playSpecialIfDue(_runId);
  }

  /// 방금 끝낸 게 호감도 이벤트였는지 (그 다음엔 일상 대화를 하나 끼워 넣음)
  bool get _justFinishedStoryEvent {
    final lastId = state.completedEventIds.lastOrNull;
    if (lastId == null) return false;
    return _eventById(lastId)?.isAffectionEvent ?? false;
  }

  Future<void> _playEvent(ScenarioEventModel event, int runId) async {
    state = state.copyWith(currentEventId: event.id);
    if (event.timeNotice != null) {
      _addSystemNotice(event.timeNotice!);
      await Future.delayed(const Duration(milliseconds: 900));
      if (runId != _runId) return;
    }
    final firstNode = _bundle.firstNodeOf(event.id);
    if (firstNode == null) {
      await _finishEvent(event, runId);
      return;
    }
    await _playNode(firstNode, runId);
  }

  /// 노드 하나의 캐릭터 대사를 재생하고, 선택지를 띄우거나(선택지가 없으면) 이벤트를 끝냅니다.
  /// [from]: 나갔다 들어왔을 때 이미 친 말풍선은 건너뜀
  Future<void> _playNode(ScriptNodeModel node, int runId, {int from = 0}) async {
    for (var i = from; i < node.characterBubbles.length; i++) {
      if (!await _typeOut(node.characterBubbles[i], () => runId == _runId)) return;
      if (i < node.characterBubbles.length - 1) _saveRun(node: node, nextBubble: i + 1);
    }

    state = state.copyWith(currentStepOrder: node.stepOrder);

    // 제작자가 지정한 단계의 대사까지 보면 그 장면(CG)이 앨범에 모임 (대화는 멈추지 않음)
    final event = _eventById(node.eventId);
    if (event != null && event.cutsceneTriggerStep == node.stepOrder) {
      _collectCutscene(event);
    }

    if (node.choices.isEmpty) {
      if (event != null) await _finishEvent(event, runId);
      return;
    }
    state = state.copyWith(currentChoices: node.choices);
    _saveRun(node: node, nextBubble: node.characterBubbles.length);
  }

  void _collectCutscene(ScenarioEventModel event) {
    if (state.unlockedCutsceneEventIds.contains(event.id)) return;
    state = state.copyWith(
      unlockedCutsceneEventIds: [...state.unlockedCutsceneEventIds, event.id],
    );
    _store.saveAlbum(_bundle.character.id, state.unlockedCutsceneEventIds);
  }

  /// 이벤트 하나를 끝내고 다음 이벤트로 넘어가거나, 공략 완료/막힘을 판정합니다.
  Future<void> _finishEvent(ScenarioEventModel event, int runId) async {
    if (event.isSpecial) {
      final id = _bundle.character.id;
      _store.saveSeenSpecials(id, {..._store.loadSeenSpecials(id), event.id}.toList());
      if (state.progress != StoryProgress.playing) return; // 공략 완료·막힘 뒤에 온 톡이면 여기서 끝
      await Future.delayed(const Duration(milliseconds: 1200));
      if (runId != _runId) return;
      await _advance(runId);
      return;
    }
    if (event.isEnding) {
      _addSystemNotice('${state.character.name} 공략 완료');
      state = state.copyWith(progress: StoryProgress.cleared);
      _saveRun(cleared: true);
      return;
    }

    state = state.copyWith(
      completedEventIds: {...state.completedEventIds, event.id}.toList(),
    );
    _saveRun();
    await Future.delayed(const Duration(milliseconds: 1200));
    if (runId != _runId) return;
    await _advance(runId);
  }

  /// 다음에 열 수 있는 이벤트를 재생하거나, 더 없으면 공략 완료/놓친 컷씬/막힘을 판정합니다.
  /// 순서: 호감도 이벤트가 끝나면 지금 단계의 일상 대화 하나 → 다음 호감도 이벤트.
  /// 다음 이벤트 조건이 안 맞으면 남은 일상 대화로 호감도를 더 쌓을 기회를 줍니다.
  Future<void> _advance(int runId) async {
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

    final remaining = _bundle.events
        .where((e) => e.isAffectionEvent && !state.completedEventIds.contains(e.id));
    if (remaining.isNotEmpty) {
      _addSystemNotice('${state.character.name}의 연락이 끊겼어요');
      state = state.copyWith(progress: StoryProgress.stuck);
      return;
    }

    if (missedCutsceneCount > 0) {
      _addSystemNotice('아직 보지 못한 장면이 $missedCutsceneCount개 남아 있어요');
      state = state.copyWith(progress: StoryProgress.missedCutscenes);
      return;
    }

    // 모든 호감도 이벤트 완료 + 모든 컷씬 수집 → 엔딩 재생
    final ending = _bundle.events.where((e) => e.isEnding).firstOrNull;
    if (ending != null) {
      await _playEvent(ending, runId);
    } else {
      _addSystemNotice('${state.character.name} 공략 완료');
      state = state.copyWith(progress: StoryProgress.cleared);
    }
  }

  /// 호감도 이벤트에 걸린 컷씬 중 아직 한 번도 못 본 개수 (지난 회차에 본 것도 인정)
  int get missedCutsceneCount => _bundle.events
      .where((e) =>
          e.isAffectionEvent &&
          e.hasCutscene &&
          !state.unlockedCutsceneEventIds.contains(e.id))
      .length;

  ScenarioEventModel? _eventById(String id) =>
      _bundle.events.where((e) => e.id == id).firstOrNull;

  void _addSystemNotice(String text) {
    final notice = ChatMessageLog(
      id: 'system_${DateTime.now().microsecondsSinceEpoch}',
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
      state.character.typingSpeedMultiplier * ref.read(chatPrefsProvider(arg)).tempo;

  /// 이 대화에서 불리는 내 별명
  String get _nickname => ref.read(chatNicknameProvider(arg));

  /// ±15% 정도 들쭉날쭉하게 (매번 똑같은 박자면 기계 같아서)
  double _jitter() => 0.85 + _random.nextDouble() * 0.3;

  /// [초보자 노트] 말풍선 하나를 사람처럼 쳐서 보냅니다.
  /// 1. 읽고 나서 뭐라고 할지 잠깐 멈칫 (입력 중 표시 없음)
  /// 2. '입력 중' 표시: 휴대폰으로 한 글자에 0.15초 정도 + 말투(speedFactor)와 캐릭터 타자 속도 반영
  /// 3. 망설이는 말(speedFactor 1.3 이상)은 치다가 멈췄다가(썼다 지웠다) 다시 침
  /// 중간에 회차가 바뀌거나 내가 끼어들면 false를 돌려주고 멈춥니다.
  Future<bool> _typeOut(ScriptBubblePiece bubble, bool Function() stillValid) async {
    final pace = _pace;
    await Future.delayed(Duration(milliseconds: (500 * pace * _jitter()).round()));
    if (!stillValid()) return false;

    final chars = Characters(CharacterModel.fillUserName(bubble.text, _nickname, charName: state.character.name)).length;
    final typingMs = ((700 + chars * 150) * bubble.speedFactor * pace * _jitter())
        .clamp(450 * pace, 9000 * pace)
        .round();

    state = state.copyWith(isCharacterTyping: true);
    if (bubble.speedFactor >= 1.3 && typingMs > 1500 * pace) {
      // 썼다 지웠다: 40% 치고 → 잠깐 멈춤 → 나머지
      await Future.delayed(Duration(milliseconds: (typingMs * 0.4).round()));
      if (!stillValid()) return false;
      state = state.copyWith(isCharacterTyping: false);
      await Future.delayed(Duration(milliseconds: (900 * pace * _jitter()).round()));
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
      id: 'char_${DateTime.now().microsecondsSinceEpoch}',
      isUser: false,
      speakerCharacterId: state.character.id,
      speakerName: state.character.name,
      text: CharacterModel.fillUserName(bubble.text, _nickname, charName: state.character.name),
      photoLabel: bubble.photoLabel,
      photoImage: bubble.photoImage,
      timestamp: DateTime.now(),
    );
    state = state.copyWith(
      isCharacterTyping: false,
      messages: [...state.messages, reply],
    );
    return true;
  }

  /// 대화방을 보고 있을 때 호출 → 안 읽은 숫자 0
  void markSeen() {
    if (state.seenMessageCount == state.messages.length) return;
    state = state.copyWith(seenMessageCount: state.messages.length);
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
  Future<bool> _typeUserDraft(String text, bool first, bool Function() stillValid) async {
    final tempo = ref.read(chatPrefsProvider(arg)).tempo;
    await Future.delayed(Duration(milliseconds: ((first ? 350 : 450) * tempo * _jitter()).round()));
    if (!stillValid()) return false;
    final chars = Characters(text).toList();
    // 긴 대사도 3초 안쪽으로 끝나게 한 번에 치는 글자 수를 늘림
    final step = (chars.length / 30).ceil().clamp(1, 10);
    for (var n = step; n < chars.length + step; n += step) {
      state = state.copyWith(userDraft: chars.take(n).join());
      await Future.delayed(Duration(milliseconds: (85 * tempo * _jitter()).round()));
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

  /// [선택지 클릭 시] 내가 고른 대답도 짧게 끊어서 연속 전송한 뒤, 캐릭터가 현실적인 타자 속도로 답장합니다.
  Future<void> selectChoice(ChoiceOption choice) async {
    final runId = _runId;
    _userBurstReplyTimer?.cancel();
    state = state.copyWith(
      currentChoices: const [],
      internalAffection: (state.internalAffection + choice.affectionDelta).clamp(0, 100),
      acquiredFlags: [
        ...state.acquiredFlags,
        if (choice.addFlag != null) choice.addFlag!,
      ],
    );

    // 1. 내 말풍선마다 입력창에 한 글자씩 쳐서 보냄 (처음엔 '1' 표시)
    for (int i = 0; i < choice.userBubbles.length; i++) {
      final piece = choice.userBubbles[i];
      final text = CharacterModel.fillUserName(piece.text, _nickname, charName: state.character.name);
      if (!await _typeUserDraft(text, i == 0, () => runId == _runId)) return;
      final myMsg = ChatMessageLog(
        id: 'user_choice_${DateTime.now().millisecondsSinceEpoch}_$i',
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
    }

    // 2. 내가 연속 전송을 마친 뒤 0.7초 후 캐릭터가 읽음('1' 일괄 사라짐)
    await Future.delayed(const Duration(milliseconds: 700));
    if (runId != _runId) return;
    _markAllUserMessagesRead();

    // 3. 다음 노드가 있으면 이어서 재생, 없으면 이 이벤트는 끝
    final nextNode =
        choice.nextNodeId != null ? _bundle.nodes[choice.nextNodeId] : null;
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
  void sendUserMessage({required String text, String? photoLabel}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty && (photoLabel == null || photoLabel.isEmpty)) return;

    final myMsg = ChatMessageLog(
      id: 'user_burst_${DateTime.now().millisecondsSinceEpoch}',
      isUser: true,
      speakerCharacterId: 'user',
      speakerName: _nickname,
      text: trimmed.isEmpty ? '사진을 보냈습니다.' : trimmed,
      photoLabel: photoLabel,
      isUnread: true, // 내가 연속으로 보내는 동안에는 계속 '1'이 유지됨!
      timestamp: DateTime.now(),
    );

    _pendingUserBurstTexts.add(
      photoLabel != null ? '[사진 전송: $photoLabel] $trimmed' : trimmed,
    );
    _isUserCurrentlyTypingText = false;

    state = state.copyWith(messages: [...state.messages, myMsg]);

    // 내가 추가로 더 칠 수 있으므로 대기 타이머를 새로고침합니다.
    _scheduleBurstReply();
  }

  /// 내가 마지막 톡을 보내고 2.2초 동안 추가 입력이 없을 때만 캐릭터가 읽고 답장을 시작합니다.
  void _scheduleBurstReply() {
    _userBurstReplyTimer?.cancel();
    _userBurstReplyTimer = Timer(const Duration(milliseconds: 2200), () {
      // 만약 유저가 아직 입력창에 다음 문장을 치고 있는 중이면 답장하지 않고 더 기다림!
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

    final combinedInput = List<String>.from(_pendingUserBurstTexts);
    _pendingUserBurstTexts.clear();

    // AI에게 보낼 '지금까지 대화'는 방금 보낸 톡('1'이 남은 것)을 뺀 기록
    final historyBeforeBurst = state.messages.where((m) => !m.isUnread).toList();

    // 1. 내가 보낸 연속 톡들의 '1'이 한꺼번에 사라짐
    _markAllUserMessagesRead();
    await Future.delayed(const Duration(milliseconds: 350));

    // 2. 내 AI 키가 있으면 Claude가 캐릭터 답장과 호감도 변화를 정하고, 없으면 준비된 문구로 답장
    final List<ScriptBubblePiece> replyPieces;
    var affectionDelta = 0;
    final byok = ref.read(byokSettingsProvider);
    if (byok.canUseAi) {
      state = state.copyWith(isCharacterTyping: true);
      try {
        final reply = await ref.read(claudeChatClientProvider).reply(
              provider: byok.provider,
              apiKey: byok.apiKey ?? '',
              relay: byok.relay,
              model: byok.model,
              character: state.character,
              stageLabel: _currentStageLabel(),
              userName: _nickname,
              userIntro: ref.read(userProfileProvider).intro,
              currentEventTitle: state.currentEventId != null
                  ? _eventById(state.currentEventId!)?.title
                  : null,
              history: historyBeforeBurst,
              newUserMessages: combinedInput,
            );
        replyPieces = [for (final text in reply.bubbles) ScriptBubblePiece(text: text)];
        affectionDelta = reply.affectionDelta;
      } on ClaudeChatException catch (e) {
        state = state.copyWith(isCharacterTyping: false);
        _addSystemNotice(e.message);
        return;
      }
    } else {
      replyPieces = _buildNaturalSplitReplies(combinedInput);
    }

    state = state.copyWith(isCharacterTyping: false);
    for (final piece in replyPieces) {
      // 만약 캐릭터가 답장하는 도중에 내가 또 새로운 톡을 쳤다면 즉시 중단하고 내 말을 먼저 받음!
      final sent = await _typeOut(piece, () => _pendingUserBurstTexts.isEmpty);
      if (!sent) return;
    }

    // AI가 판정한 호감도 변화는 답장을 다 보낸 뒤 반영 (화면에는 숫자로 안 보임)
    if (affectionDelta != 0) {
      state = state.copyWith(
        internalAffection: (state.internalAffection + affectionDelta).clamp(0, 100),
      );
    }
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

  /// 유저가 연속으로 보낸 메시지 묶음에 대해 실제 사람처럼 짧게 끊어 치는 답장을 구성합니다.
  List<ScriptBubblePiece> _buildNaturalSplitReplies(List<String> userBurst) {
    final joined = userBurst.join(' ');

    if (joined.contains('사진 전송')) {
      return const [
        ScriptBubblePiece(text: '오 뭔데', speedFactor: 0.5),
        ScriptBubblePiece(text: '방금 찍은 거야? 분위기 좋네', speedFactor: 0.9),
        ScriptBubblePiece(
          text: '나도 지금 내 앞에 찍어서 보여줄까',
          photoLabel: '소파 위에서 배를 까고 자는 회색 고양이 두부 사진',
          speedFactor: 1.2,
        ),
      ];
    }

    if (userBurst.length >= 2) {
      return [
        const ScriptBubblePiece(text: 'ㅋㅋㅋ 천천히 말해 숨차겠다', speedFactor: 0.6),
        ScriptBubblePiece(
          text: '그래도 네가 할 말 다 해줘서 좋다. 지금 어디쯤이야?',
          speedFactor: 1.0,
        ),
      ];
    }

    return [
      const ScriptBubblePiece(text: '응 보고 있어', speedFactor: 0.5),
      ScriptBubblePiece(
        text: '아까부터 계속 폰 붙잡고 네 연락 기다렸거든',
        speedFactor: 1.1,
      ),
    ];
  }

  void toggleDirectInputMode(bool enabled) {
    state = state.copyWith(isByokAiModeEnabled: enabled);
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
