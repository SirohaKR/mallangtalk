import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/claude_chat_client.dart';
import '../../core/storage/local_store.dart';
import '../../shared/models/mallangtalk_models.dart';
import '../settings/byok_settings.dart';

/// [초보자 노트] 샘플 시나리오 JSON 파일을 읽어오는 FutureProvider입니다.
/// 지금은 앱 안의 assets 파일을 읽지만, 4단계에서 서버가 생기면 이 부분만 API 호출로 바꾸면 됩니다.
final scenarioBundleProvider = FutureProvider<ScenarioBundle>((ref) async {
  final raw = await rootBundle.loadString('assets/scenarios/sample_character.json');
  return ScenarioBundle.fromJson(jsonDecode(raw) as Map<String, dynamic>);
});

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
  /// 지금 전체 화면으로 띄워져 있는 컷씬(CG)의 이벤트
  final ScenarioEventModel? activeCutscene;
  /// 지금까지 수집한 컷씬의 이벤트 ID (앨범용, '다시 하기'를 해도 유지됨)
  final List<String> unlockedCutsceneEventIds;
  final StoryProgress progress;

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
    this.activeCutscene,
    this.unlockedCutsceneEventIds = const [],
    this.progress = StoryProgress.playing,
  });

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
    ScenarioEventModel? activeCutscene,
    bool clearActiveCutscene = false,
    List<String>? unlockedCutsceneEventIds,
    StoryProgress? progress,
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
      activeCutscene:
          clearActiveCutscene ? null : (activeCutscene ?? this.activeCutscene),
      unlockedCutsceneEventIds:
          unlockedCutsceneEventIds ?? this.unlockedCutsceneEventIds,
      progress: progress ?? this.progress,
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
class ChatRoomNotifier extends Notifier<ChatRoomState> {
  late ScenarioBundle _bundle;
  late LocalStore _store;

  /// 내가 연속으로 톡을 보낼 때 상대방 답장을 보류하는 디바운스 타이머
  Timer? _userBurstReplyTimer;
  /// 내가 지금 입력창에 글자를 치고 있는지 여부
  bool _isUserCurrentlyTypingText = false;
  /// 내가 연속으로 보낸 메시지들을 모아두는 버퍼
  final List<String> _pendingUserBurstTexts = [];
  /// 컷씬 팝업이 닫힐 때까지 대화 진행을 멈춰두는 장치
  Completer<void>? _cutsceneClosed;
  /// '다시 하기'를 누르면 숫자가 바뀌어서, 이전 회차에서 아직 돌던 연출을 멈추게 함
  int _runId = 0;

  @override
  ChatRoomState build() {
    ref.onDispose(() {
      _userBurstReplyTimer?.cancel();
    });

    _bundle = ref.watch(scenarioBundleProvider).requireValue;
    _store = ref.watch(localStoreProvider);
    final characterId = _bundle.character.id;
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
      );
      if (!saved.cleared) Future.microtask(() => _advance(_runId));
      return restored;
    }
    Future.microtask(() => _advance(_runId));
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

  /// 처음부터 다시 플레이 (수집한 컷씬은 그대로 남김)
  void restart() {
    _runId++;
    _userBurstReplyTimer?.cancel();
    _pendingUserBurstTexts.clear();
    _cutsceneClosed?.complete();
    _cutsceneClosed = null;
    state = _freshRunState(unlockedCutscenes: state.unlockedCutsceneEventIds)
        .copyWith(isByokAiModeEnabled: state.isByokAiModeEnabled);
    _store.clearRun(_bundle.character.id);
    _advance(_runId);
  }

  /// 이벤트 경계마다 진행 기록을 브라우저에 저장
  void _saveRun({bool cleared = false}) {
    _store.saveRun(
      _bundle.character.id,
      SavedRun(
        affection: state.internalAffection,
        flags: state.acquiredFlags,
        completedEventIds: state.completedEventIds,
        messages: state.messages,
        cleared: cleared,
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

  bool _isUnlocked(ScenarioEventModel event) {
    return state.internalAffection >= event.requiredAffection &&
        event.requiredFlags.every(state.acquiredFlags.contains);
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
  Future<void> _playNode(ScriptNodeModel node, int runId) async {
    for (final bubble in node.characterBubbles) {
      state = state.copyWith(isCharacterTyping: true);
      await Future.delayed(
        _calculateRealisticTypingDelay(bubble.text, bubble.speedFactor),
      );
      if (runId != _runId) return;

      final reply = ChatMessageLog(
        id: 'char_${DateTime.now().microsecondsSinceEpoch}',
        isUser: false,
        speakerCharacterId: node.speakerCharacterId,
        speakerName: state.character.name,
        text: bubble.text,
        photoLabel: bubble.photoLabel,
        timestamp: DateTime.now(),
      );
      state = state.copyWith(
        isCharacterTyping: false,
        messages: [...state.messages, reply],
      );
      // 다음 말풍선을 치기 전 잠깐의 자연스러운 호흡 간격
      await Future.delayed(const Duration(milliseconds: 260));
      if (runId != _runId) return;
    }

    state = state.copyWith(currentStepOrder: node.stepOrder);

    // 제작자가 지정한 단계의 대사가 끝나면 컷씬(CG) 팝업 → 닫을 때까지 대기
    final event = _eventById(node.eventId);
    if (event != null && event.cutsceneTriggerStep == node.stepOrder) {
      await _showCutscene(event);
      if (runId != _runId) return;
    }

    if (node.choices.isEmpty) {
      if (event != null) await _finishEvent(event, runId);
      return;
    }
    state = state.copyWith(currentChoices: node.choices);
  }

  Future<void> _showCutscene(ScenarioEventModel event) async {
    await Future.delayed(const Duration(milliseconds: 500));
    _cutsceneClosed = Completer<void>();
    state = state.copyWith(
      activeCutscene: event,
      unlockedCutsceneEventIds: {
        ...state.unlockedCutsceneEventIds,
        event.id,
      }.toList(),
    );
    _store.saveAlbum(_bundle.character.id, state.unlockedCutsceneEventIds);
    await _cutsceneClosed!.future;
  }

  void closeCutscene() {
    state = state.copyWith(clearActiveCutscene: true);
    _cutsceneClosed?.complete();
    _cutsceneClosed = null;
  }

  /// 이벤트 하나를 끝내고 다음 이벤트로 넘어가거나, 공략 완료/막힘을 판정합니다.
  Future<void> _finishEvent(ScenarioEventModel event, int runId) async {
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
  Future<void> _advance(int runId) async {
    final next = _nextPlayableEvent();
    if (next != null) {
      await _playEvent(next, runId);
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

  /// 글자 수와 빠르기 계수(speedFactor)를 바탕으로 현실적인 타자 시간(ms)을 계산합니다.
  Duration _calculateRealisticTypingDelay(String text, double speedFactor) {
    final baseMs = 380;
    final perCharMs = 52;
    final rawMs = (baseMs + (text.length * perCharMs)) *
        speedFactor *
        state.character.typingSpeedMultiplier;
    return Duration(milliseconds: rawMs.clamp(350, 2600).toInt());
  }

  /// 모든 내 안 읽음('1') 말풍선을 일괄 '읽음' 처리합니다.
  void _markAllUserMessagesRead() {
    final updated = state.messages
        .map((m) => (m.isUser && m.isUnread) ? m.copyWith(isUnread: false) : m)
        .toList();
    state = state.copyWith(messages: updated);
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

    // 1. 내 말풍선들을 짧게 끊어서 연속 전송 (처음엔 '1' 표시)
    for (int i = 0; i < choice.userBubbles.length; i++) {
      final piece = choice.userBubbles[i];
      if (i > 0) {
        await Future.delayed(const Duration(milliseconds: 380));
        if (runId != _runId) return;
      }
      final myMsg = ChatMessageLog(
        id: 'user_choice_${DateTime.now().millisecondsSinceEpoch}_$i',
        isUser: true,
        speakerCharacterId: 'user',
        speakerName: '나',
        text: piece.text,
        photoLabel: piece.photoLabel,
        isUnread: true,
        timestamp: DateTime.now(),
      );
      state = state.copyWith(messages: [...state.messages, myMsg]);
    }

    // 2. 내가 연속 전송을 마친 뒤 0.7초 후 캐릭터가 읽음('1' 일괄 사라짐)
    await Future.delayed(const Duration(milliseconds: 700));
    if (runId != _runId) return;
    _markAllUserMessagesRead();

    // 3. 다음 노드가 있으면 이어서 재생, 없으면 이 이벤트는 끝
    final nextNode =
        choice.nextNodeId != null ? _bundle.nodes[choice.nextNodeId] : null;
    if (nextNode != null) {
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
      speakerName: '나',
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
    if (byok.hasKey) {
      state = state.copyWith(isCharacterTyping: true);
      try {
        final reply = await ref.read(claudeChatClientProvider).reply(
              apiKey: byok.apiKey!,
              model: byok.model,
              character: state.character,
              stageLabel: _currentStageLabel(),
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

    for (final piece in replyPieces) {
      // 만약 캐릭터가 답장하는 도중에 내가 또 새로운 톡을 쳤다면 즉시 중단하고 내 말을 먼저 받음!
      if (_pendingUserBurstTexts.isNotEmpty) {
        state = state.copyWith(isCharacterTyping: false);
        return;
      }

      state = state.copyWith(isCharacterTyping: true);
      await Future.delayed(
        _calculateRealisticTypingDelay(piece.text, piece.speedFactor),
      );

      if (_pendingUserBurstTexts.isNotEmpty) {
        state = state.copyWith(isCharacterTyping: false);
        return;
      }

      final replyMsg = ChatMessageLog(
        id: 'char_reply_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        speakerCharacterId: state.character.id,
        speakerName: state.character.name,
        text: piece.text,
        photoLabel: piece.photoLabel,
        timestamp: DateTime.now(),
      );

      state = state.copyWith(
        isCharacterTyping: false,
        messages: [...state.messages, replyMsg],
      );

      await Future.delayed(const Duration(milliseconds: 280));
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

final chatRoomProvider = NotifierProvider<ChatRoomNotifier, ChatRoomState>(
  ChatRoomNotifier.new,
);
