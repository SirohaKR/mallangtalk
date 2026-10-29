import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/models/mallangtalk_models.dart';
import '../../shared/widgets/character_avatar.dart';
import '../../shared/widgets/photo_viewer.dart';
import '../../shared/utils/file_io.dart';
import '../home/friends_screen.dart';
import '../library/character_library.dart';
import '../settings/byok_settings.dart';
import '../settings/user_profile.dart';
import 'start_chat.dart';
import 'chat_ai_sheet.dart';
import 'chat_notifier.dart';
import 'chat_theme.dart';
import 'romance_settings.dart';
import '../../shared/utils/dialogue_input.dart';

final chatPhotoPickerProvider =
    Provider<Future<String?> Function(BuildContext)>((ref) => pickPhoto);

/// [초보자 노트] 리얼 메신저 스타일 채팅 화면입니다.
/// - 호감도 점수나 (+호감도), (실시간 AI 응답), 괄호 지문()을 모두 제거해 실제 카톡처럼 몰입감을 높였습니다.
/// - 유저나 캐릭터가 찍은 사진이 대화방 말풍선 안에 직접 올라오며, 클릭하면 크게 볼 수 있습니다.
/// - 내가 단문으로 여러 번 연속해서 보내는 동안에는 캐릭터가 답장하지 않고 기다려 줍니다.
/// - 상단 버튼으로 앨범(모은 컷씬)과 설정(내 AI 키)으로 이동합니다.
/// 지운 캐릭터의 주소로 들어오면 안내만 보여주고, 있으면 대화방을 엶
class ChatRoomPage extends ConsumerWidget {
  const ChatRoomPage({super.key, required this.characterId, this.free = false});

  final String characterId;

  /// 자유대화 방이면 true (스토리 방과 따로)
  final bool free;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exists = ref
        .watch(characterBundleProvider(characterId).select((b) => b != null));
    if (!exists) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(
            child: Text('이 캐릭터는 내 캐릭터 목록에 없어요',
                style: AppTextStyles.systemNotice)),
      );
    }
    return ChatScreen(
        key: ValueKey(free),
        roomId: free ? freeRoomId(characterId) : characterId);
  }
}

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.roomId,
    this.embedded = false,
    this.onSwitchRoom,
  });

  /// 스토리 방은 캐릭터 ID, 자유대화 방은 캐릭터 ID#free
  final String roomId;

  /// PC 채팅 탭 우측 분할 화면에 내장되어 열렸는지 여부
  final bool embedded;

  /// 내장 모드에서 스토리 ↔ 자유대화 방 전환 시 호출
  final ValueChanged<String>? onSwitchRoom;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  /// 엔터로 보낸 뒤에도 입력창에 커서를 그대로 둬서 연달아 칠 수 있게 함
  final FocusNode _inputFocus = FocusNode();
  double _lastBottomInset = 0;
  ChatMessageLog? _replyTarget;

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId) _replyTarget = null;
  }

  @override
  void initState() {
    super.initState();
    // 대화방에 들어오면 채팅방 목록 맨 위로 + 지금까지 온 톡은 읽음
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!widget.embedded) {
        ref.read(chatRoomsProvider.notifier).open(widget.roomId);
      }
      final notifier = ref.read(chatRoomProvider(widget.roomId).notifier);
      notifier.markSeen();
      notifier.checkSpecialEvents(); // 이야기가 멈춰 있어도 특별한 시간이면 톡이 옴
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _send(ChatRoomNotifier notifier) {
    if (!_ensureAiReady()) return;
    if (!notifier.sendUserMessage(
        text: _inputController.text, replyTo: _replyTarget)) return;
    setState(() => _replyTarget = null);
    _inputController.clear();
    notifier.onUserTypingChanged('');
    // 전송할 때 웹 입력 요소를 다시 focus하면 모바일 브라우저가 화면을
    // 입력칸 쪽으로 밀 수 있다. 기존 포커스는 TextFieldTapRegion으로 유지한다.
  }

  /// 목록을 거꾸로(reverse) 그려서 맨 아래(최근 톡)가 0 위치. 다시 들어와도 최근 톡부터 보임
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && _scrollController.offset > 0) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  bool _ensureAiReady() {
    if (ref.read(byokSettingsProvider).canUseAi) return true;
    showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('API 키를 등록해 주세요'),
              content: const Text('자유대화를 시작하려면 사용할 AI의 API 키를 등록해 주세요.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('취소')),
                FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      showChatAiSheet(context,
                          accent: Theme.of(context).colorScheme.primary);
                    },
                    child: const Text('API 키 등록')),
              ],
            ));
    return false;
  }

  bool _pickingPhoto = false;
  Future<void> _showUserPhotoSenderSheet(ChatRoomNotifier notifier) async {
    if (_pickingPhoto || !_ensureAiReady()) return;
    _pickingPhoto = true;
    final room = widget.roomId;
    try {
      final image = await ref.read(chatPhotoPickerProvider)(context);
      if (!mounted || room != widget.roomId || image == null) return;
      if (image.length > 1400000) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('사진이 너무 커요. 더 작은 영역으로 잘라 주세요.')));
        return;
      }
      if (!_ensureAiReady()) return;
      if (notifier.sendUserMessage(
          text: _inputController.text,
          photoLabel: '첨부한 사진',
          photoImage: image,
          replyTo: _replyTarget)) {
        setState(() => _replyTarget = null);
        _inputController.clear();
        notifier.onUserTypingChanged('');
        _scrollToBottom();
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('사진을 불러오지 못했어요. 다시 선택해 주세요.')));
    } finally {
      _pickingPhoto = false;
    }
  }

  /// 이 대화방에 올라온 사진들을 크게 보기 (누른 사진부터, 옆으로 밀면 다른 사진)
  Future<void> _openPhotoViewer(
      ChatMessageLog tapped,
      ChatRoomState chatState,
      ScenarioBundle? bundle,
      ChatTheme theme,
      ChatRoomNotifier notifier) async {
    final photos = chatState.messages.where((m) => m.hasPhoto).toList();
    final start = photos.indexWhere((m) => m.id == tapped.id);
    final albumGroups = {
      for (final p in bundle?.albumPhotos ?? const <AlbumPhoto>[])
        p.label: p.group
    };
    notifier.openPhotoPreview(tapped.photoLabel!);
    await showPhotoViewer(
      context,
      accent: theme.accent,
      initialIndex: start < 0 ? 0 : start,
      items: [
        for (final m in photos)
          PhotoViewerItem(
            label: m.photoLabel!,
            image: bundle?.photoFor(m.photoImage, m.photoLabel),
            chip: albumGroups[m.photoLabel!.trim()],
            caption:
                '${photoTimeLabel(m.timestamp)}에 ${m.isUser ? '보냄' : '받음 · ${m.speakerName}'}',
          ),
      ],
    );
    notifier.closePhotoPreview();
  }

  @override
  Widget build(BuildContext context) {
    final roomId = widget.roomId;
    final id = characterIdOfRoom(roomId);
    final free = isFreeRoom(roomId);
    final chatState = ref.watch(chatRoomProvider(roomId));
    final service = chatState.character.isService;
    final notifier = ref.read(chatRoomProvider(roomId).notifier);
    final hasApiKey = ref.watch(byokSettingsProvider.select((s) => s.canUseAi));
    final bundle = ref.watch(characterBundleProvider(id));
    final theme = ChatTheme.of(chatState.character);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    if (bottomInset > _lastBottomInset) {
      _scrollToBottom();
    }
    _lastBottomInset = bottomInset;

    ref.listen<ChatRoomState>(chatRoomProvider(roomId), (prev, next) {
      if (prev?.messages.length != next.messages.length ||
          prev?.isCharacterTyping != next.isCharacterTyping ||
          prev?.progress != next.progress) {
        _scrollToBottom();
      }
      if (prev?.messages.length != next.messages.length) {
        // 보고 있는 대화방에 온 톡은 바로 읽음 처리
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) notifier.markSeen();
        });
      }
    });

    final keyOccurrences = <String, int>{};
    final messageRowKeys = <String>[];
    for (final message in chatState.messages) {
      final occurrence =
          keyOccurrences.update(message.id, (n) => n + 1, ifAbsent: () => 0);
      messageRowKeys.add('reply_target_${message.id}_$occurrence');
    }
    final rowIndices = <String, int>{
      for (var i = 0; i < messageRowKeys.length; i++)
        messageRowKeys[i]: messageRowKeys.length -
            1 -
            i +
            (chatState.isCharacterTyping ? 1 : 0),
    };
    final chatColumn = Column(
      children: [
        // 1. 대화창 메시지 리스트
        Expanded(
          child: free &&
                  chatState.messages.isEmpty &&
                  !chatState.isCharacterTyping
              ? _FreeRoomIntro(
                  name: chatState.character.name, accent: theme.accent)
              : ListView.builder(
                  controller: _scrollController,
                  findChildIndexCallback: (key) {
                    if (key is! ValueKey<String>) return null;
                    if (key.value == 'typing_indicator') {
                      return chatState.isCharacterTyping ? 0 : null;
                    }
                    return rowIndices[key.value];
                  },
                  reverse: true,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.manual,
                  padding: AppSpacing.screenPadding,
                  itemCount: chatState.messages.length +
                      (chatState.isCharacterTyping ? 1 : 0),
                  itemBuilder: (context, reversedIndex) {
                    final typing = chatState.isCharacterTyping ? 1 : 0;
                    if (reversedIndex == 0 && typing == 1) {
                      return const _TypingIndicatorBubble(
                          key: ValueKey('typing_indicator'));
                    }
                    final index = chatState.messages.length -
                        1 -
                        (reversedIndex - typing);
                    final msg = chatState.messages[index];
                    if (msg.isHidden)
                      return SizedBox.shrink(
                          key: ValueKey(messageRowKeys[index]));
                    if (msg.isSystem) {
                      if (msg.isConversationBreak) {
                        final time = TimeOfDay.fromDateTime(msg.timestamp)
                            .format(context);
                        return Padding(
                          key: ValueKey(messageRowKeys[index]),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Row(
                            children: [
                              const Expanded(child: Divider()),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: Text('${msg.text} · $time',
                                    style: AppTextStyles.systemNotice),
                              ),
                              const Expanded(child: Divider()),
                            ],
                          ),
                        );
                      }
                      return KeyedSubtree(
                          key: ValueKey(messageRowKeys[index]),
                          child: _SystemNoticeRow(text: msg.text));
                    }
                    final image =
                        bundle?.photoFor(msg.photoImage, msg.photoLabel);
                    return GestureDetector(
                        key: ValueKey(messageRowKeys[index]),
                        onLongPress: free
                            ? () {
                                setState(() => _replyTarget = msg);
                                _inputFocus.requestFocus();
                              }
                            : null,
                        child: _MessageBubbleRow(
                          message: msg,
                          theme: theme,
                          photoUrl: image,
                          maxBubbleWidth: screenWidth >= 720 ? 420 : 290,
                          onPhotoTap: msg.hasPhoto
                              ? () => _openPhotoViewer(
                                  msg, chatState, bundle, theme, notifier)
                              : null,
                        ));
                  },
                ),
        ),

        // 2. 하단 선택지 패널 & 연속 전송 가능한 직접 입력바 + 카메라 버튼
        Container(
          padding: AppSpacing.screenPadding,
          decoration: const BoxDecoration(
            color: AppColors.surfaceWhite,
            border: Border(top: BorderSide(color: AppColors.borderLight)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_replyTarget case final target?)
                Padding(
                  key: const ValueKey('reply_preview'),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    const Icon(Icons.reply_rounded),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(
                            '${target.speakerName}에게 답장\n${target.text}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis)),
                    IconButton(
                        tooltip: '답장 취소',
                        onPressed: () => setState(() => _replyTarget = null),
                        icon: const Icon(Icons.close)),
                  ]),
                ),
              if (!free &&
                  !service &&
                  chatState.progress != StoryProgress.playing &&
                  !chatState.isReplaying &&
                  !chatState.isScriptPlaying &&
                  chatState.currentChoices.isEmpty &&
                  !chatState.isCharacterTyping)
                _RunEndPanel(
                  progress: chatState.progress,
                  endingTitle: bundle?.events
                      .where((e) => e.isEnding)
                      .firstOrNull
                      ?.title,
                  received: (bundle?.albumPhotos.length ?? 0) -
                      notifier.missedPhotoCount,
                  totalPhotos: bundle?.albumPhotos.length ?? 0,
                  replayable: notifier.replayableEvents,
                  accent: theme.accent,
                  onReplay: notifier.replayEvent,
                  onRestart: notifier.restart,
                ),
              if (chatState.currentChoices.isNotEmpty) ...[
                for (final choice in chatState.currentChoices)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppSpacing.choiceRadius),
                          side:
                              BorderSide(color: theme.choiceBorder, width: 1.2),
                        ),
                      ),
                      onPressed: () => notifier.selectChoice(choice),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // 예전 회차에 한 번도 안 고른 선택지 (공략을 끝낸 뒤부터 보임)
                          if (chatState.sparkleChoiceIds
                              .contains(choice.id)) ...[
                            Icon(Icons.auto_awesome_rounded,
                                key: ValueKey('choice_new_${choice.id}'),
                                size: 16,
                                color: const Color(0xFFF2B13C)),
                            const SizedBox(width: 6),
                          ],
                          if (choice.userBubbles.any((b) => b.hasPhoto)) ...[
                            const Icon(Icons.photo_camera_outlined, size: 17),
                            const SizedBox(width: 6),
                          ],
                          Flexible(child: Text(choice.buttonLabel)),
                        ],
                      ),
                    ),
                  ),
              ],
              if (chatState.isByokAiModeEnabled && chatState.canRetryFreeTalk)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: OutlinedButton.icon(
                    onPressed: notifier.retryFreeTalk,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('다시 보내기'),
                  ),
                ),
              if (chatState.isByokAiModeEnabled && !hasApiKey)
                GestureDetector(
                  onTap: () => showChatAiSheet(context, accent: theme.accent),
                  child: const Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: Text(
                      'AI 키를 넣으면 진짜 AI가 답해요. 눌러서 연결하기 →',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.systemNotice,
                    ),
                  ),
                ),
              // 서비스 말랑이: 지금 바로 새 문구 한 통
              if (service && (chatState.character.service?.reroll ?? false))
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: OutlinedButton.icon(
                      key: const ValueKey('service_reroll'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Color.lerp(
                            theme.accent, AppColors.textPrimary, 0.3),
                        side: BorderSide(color: theme.accent, width: 1.5),
                        shape: const StadiumBorder(),
                      ),
                      onPressed: chatState.isCharacterTyping
                          ? null
                          : notifier.rerollService,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('한 번 더 뽑기'),
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              _InputBar(
                // 스토리 방이거나 선택지 대사가 쳐지는 중이면 보이기만 하고 못 누름
                enabled: chatState.isByokAiModeEnabled &&
                    chatState.userDraft.isEmpty,
                draft: chatState.userDraft,
                controller: _inputController,
                focusNode: _inputFocus,
                autofocus: screenWidth >= AppSpacing.studioSplitBreakpoint,
                onChanged: notifier.onUserTypingChanged,
                onCamera: () => _showUserPhotoSenderSheet(notifier),
                onSend: () => _send(notifier),
                accent: theme.accent,
              ),
            ],
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        // 대표색 윗줄
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: Container(height: 3, color: theme.accent),
        ),
        leading: widget.embedded
            ? null
            : IconButton(
                tooltip: '채팅방 목록',
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/chats'),
              ),
        titleSpacing: widget.embedded ? AppSpacing.lg : 0,
        title: Row(
          children: [
            // 사진을 누르면 캐릭터 프로필
            GestureDetector(
              onTap: () {
                final entry =
                    ref.read(characterLibraryProvider.notifier).byId(id);
                if (entry != null)
                  showCharacterProfile(context, entry, inChat: true);
              },
              child: Tooltip(
                message: '프로필 보기',
                child:
                    CharacterAvatar(character: chatState.character, radius: 18),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                          child: Text(chatState.character.name,
                              overflow: TextOverflow.ellipsis)),
                      if (service) ...[
                        const SizedBox(width: 6),
                        const _ServiceBadge(),
                      ],
                    ],
                  ),
                  // 자유대화 방이면 상태 메시지 대신 지금 쓰는 AI (누르면 바꾸기)
                  if (free ||
                      (service && chatState.character.service?.mode == 'ai'))
                    GestureDetector(
                      key: const ValueKey('chat_ai_pill'),
                      onTap: () =>
                          showChatAiSheet(context, accent: theme.accent),
                      child: Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Color.lerp(
                              AppColors.surfaceWhite, theme.accent, 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${free && ref.watch(romanceSettingsProvider(id)) != RomanceTone.basic && !hasMinorAge(chatState.character) ? '성인 · ${ref.watch(romanceSettingsProvider(id)).label} · ' : ''}${service ? 'AI' : '자유대화'} · ${aiModelName(ref.watch(byokSettingsProvider))} ▾',
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.messageTime.copyWith(
                            color: Color.lerp(
                                theme.accent, AppColors.textPrimary, 0.35),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    )
                  else
                    Text(
                      CharacterModel.fillUserName(
                          chatState.character.statusMessage, '너',
                          charName: chatState.character.name),
                      style: AppTextStyles.messageTime,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (!service)
            IconButton(
              tooltip: '앨범',
              onPressed: () => context.push('/chat/$id/album'),
              icon: const Icon(Icons.photo_library_outlined),
            ),
          PopupMenuButton<String>(
            tooltip: '대화 설정',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) {
              switch (value) {
                case 'nickname':
                  askChatNickname(context, chatState.character);
                case 'tempo':
                  pickChatTempo(context, chatState.character);
                case 'ai':
                  showChatAiSheet(context, accent: theme.accent);
                case 'end_scene':
                  notifier.endConversation();
                  setState(() => _replyTarget = null);
                case 'romance':
                  showRomanceSettings(context, chatState.character);
                case 'switch':
                  final nextRoom = free ? id : freeRoomId(id);
                  ref.read(chatRoomsProvider.notifier).open(nextRoom);
                  if (widget.embedded && widget.onSwitchRoom != null) {
                    widget.onSwitchRoom!(nextRoom);
                  } else {
                    // 스토리 방 ↔ 자유대화 방 (지금 방은 닫고 다른 방으로)
                    context.pushReplacement(free ? '/chat/$id' : '/free/$id');
                  }
                case 'restart':
                  notifier.restart();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'nickname',
                child: Text('내 별명·설정: ${ref.read(chatNicknameProvider(id))}'),
              ),
              const PopupMenuItem(value: 'tempo', child: Text('대화 속도')),
              if (free)
                const PopupMenuItem(value: 'romance', child: Text('로맨스 분위기')),
              if (free)
                const PopupMenuItem(
                    value: 'end_scene', child: Text('대화 끝 구분선 넣기')),
              if (!service)
                PopupMenuItem(
                    value: 'switch',
                    child: Text(free ? '스토리 대화방으로' : '자유대화 방 열기')),
              PopupMenuItem(
                  value: 'ai',
                  child: Text(service ? '답장 AI 고르기' : '자유대화 AI 고르기')),
              PopupMenuItem(
                  value: 'restart',
                  child: Text(free || service ? '대화 비우기' : '처음부터 다시')),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: widget.embedded || screenWidth < 720
          ? chatColumn
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 840),
                child: Container(
                  decoration: const BoxDecoration(
                    border: Border.symmetric(
                      vertical: BorderSide(color: AppColors.borderLight),
                    ),
                  ),
                  child: chatColumn,
                ),
              ),
            ),
    );
  }
}

/// 카메라 + 입력칸 + 전송 버튼. 꺼져 있으면 흐리게 보이고 눌리지 않음
/// [draft]가 있으면 선택지 대사가 입력칸에 쳐지는 모습을 보여 줌
class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.enabled,
    required this.draft,
    required this.controller,
    required this.focusNode,
    required this.autofocus,
    required this.onChanged,
    required this.onCamera,
    required this.onSend,
    required this.accent,
  });

  final Color accent;
  final bool enabled;
  final String draft;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool autofocus;
  final ValueChanged<String> onChanged;
  final VoidCallback onCamera;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final typing = draft.isNotEmpty;
    return Row(
      children: [
        IconButton(
          tooltip: '갤러리 사진 첨부',
          onPressed: enabled ? onCamera : null,
          icon: Icon(
            Icons.camera_alt_outlined,
            color: enabled ? AppColors.primaryNavy : AppColors.textMuted,
          ),
        ),
        Expanded(
          child: enabled
              ? TextField(
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: autofocus,
                  scrollPadding: EdgeInsets.zero,
                  onChanged: onChanged,
                  textInputAction: TextInputAction.send,
                  decoration: const InputDecoration(
                    hintText: '메시지 또는 (행동·상황)을 입력하세요',
                  ),
                  // 엔터를 눌러도 키보드·커서가 내려가지 않게 (웹에서 연속 입력)
                  onEditingComplete: () {},
                  onSubmitted: (_) => onSend(),
                )
              : InputDecorator(
                  key: const ValueKey('locked_input'),
                  isEmpty: !typing,
                  decoration: const InputDecoration(
                    enabled: false,
                    hintText: '선택지를 골라 대답해요',
                  ),
                  child: Text(draft, style: AppTextStyles.chatBubbleBody),
                ),
        ),
        const SizedBox(width: 8),
        TextFieldTapRegion(
          child: IconButton.filled(
            style: IconButton.styleFrom(backgroundColor: accent),
            onPressed: enabled ? onSend : null,
            icon: const Icon(Icons.send_rounded),
          ),
        ),
      ],
    );
  }
}

/// 말풍선(텍스트 + 대화방 사진 카드 + 읽음 '1') 위젯
class _MessageBubbleRow extends StatelessWidget {
  final ChatMessageLog message;
  final ChatTheme theme;

  /// 진짜 사진 주소 (없으면 설명 카드)
  final String? photoUrl;
  final double maxBubbleWidth;
  final VoidCallback? onPhotoTap;

  const _MessageBubbleRow({
    required this.message,
    required this.theme,
    this.photoUrl,
    this.maxBubbleWidth = 290,
    this.onPhotoTap,
  });

  @override
  Widget build(BuildContext context) {
    final photo =
        message.hasPhoto ? CharacterImage.providerFor(photoUrl ?? '') : null;
    final isUser = message.isUser;
    final bubbleColor = isUser ? theme.myBubble : AppColors.partnerBubble;
    final bubbleText = ChatTheme.readableOn(bubbleColor);
    final darkBubble =
        ThemeData.estimateBrightnessForColor(bubbleColor) == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isUser && message.isUnread)
            const Padding(
              padding: EdgeInsets.only(right: 6, bottom: 2),
              child: Text('1', style: AppTextStyles.unreadCount),
            ),
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: maxBubbleWidth),
              padding: AppSpacing.bubblePadding,
              decoration: BoxDecoration(
                color: isUser ? theme.myBubble : AppColors.partnerBubble,
                borderRadius: BorderRadius.circular(AppSpacing.bubbleRadius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isUser && stageDirectionOf(message.text) != null)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('상황 연출',
                            style: TextStyle(fontSize: 11, color: bubbleText))),
                  if (message.replyToText != null)
                    Container(
                      key: ValueKey('quoted_${message.id}'),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: darkBubble
                              ? Colors.white.withValues(alpha: 0.12)
                              : Colors.black.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(
                          '${message.replyToName ?? "상대"}에게 답장\n${message.replyToText}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: bubbleText)),
                    ),
                  // 사진이 포함된 말풍선이면 대화방 안에 사진 카드 표시!
                  if (photo != null) ...[
                    GestureDetector(
                      onTap: onPhotoTap,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image(
                            image: photo,
                            gaplessPlayback: true,
                            width: 220,
                            fit: BoxFit.cover,
                            semanticLabel: message.photoLabel,
                          ),
                        ),
                      ),
                    ),
                  ] else if (message.hasPhoto) ...[
                    GestureDetector(
                      onTap: onPhotoTap,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: AppColors.scaffoldBackground,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.borderLight),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.photo_camera_back_rounded,
                              size: 36,
                              color: theme.accent,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              message.photoLabel!,
                              textAlign: TextAlign.center,
                              style: AppTextStyles.systemNotice,
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              '탭하여 사진 크게 보기',
                              style: AppTextStyles.messageTime,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (message.text.isNotEmpty || !message.hasPhoto)
                    Text(message.text,
                        style: AppTextStyles.chatBubbleBody.copyWith(
                            color: isUser ? theme.myText : null,
                            fontStyle:
                                isUser && stageDirectionOf(message.text) != null
                                    ? FontStyle.italic
                                    : FontStyle.normal)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 상대방이 타자를 치고 있을 때 뜨는 말풍선 (점 세 개가 차례로 통통 튐)
class _TypingIndicatorBubble extends StatefulWidget {
  const _TypingIndicatorBubble({super.key});

  @override
  State<_TypingIndicatorBubble> createState() => _TypingIndicatorBubbleState();
}

class _TypingIndicatorBubbleState extends State<_TypingIndicatorBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.partnerBubble,
          borderRadius: BorderRadius.circular(AppSpacing.bubbleRadius),
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 5),
                Transform.translate(
                  offset: Offset(
                      0, -3 * _bounce((_controller.value - i * 0.18) % 1.0)),
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: AppColors.textMuted.withValues(
                        alpha: 0.45 +
                            0.55 *
                                _bounce((_controller.value - i * 0.18) % 1.0),
                      ),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 0~1 사이에서 앞쪽 40% 동안만 한 번 튀어 오름
  static double _bounce(double t) {
    if (t < 0 || t > 0.4) return 0;
    final x = t / 0.4;
    return 4 * x * (1 - x);
  }
}

/// 대화방 가운데 뜨는 안내 문구 (시간 경과, 공략 완료 등)
class _SystemNoticeRow extends StatelessWidget {
  final String text;

  const _SystemNoticeRow({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.primaryNavy.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text, style: AppTextStyles.systemNotice),
      ),
    );
  }
}

/// 한 회차가 끝났을 때 하단에 뜨는 결과 패널 (공략 완료 / 놓친 컷씬 / 진행 막힘)
class _RunEndPanel extends StatelessWidget {
  final StoryProgress progress;
  final String? endingTitle;
  final int received;
  final int totalPhotos;
  final List<ReplayableEvent> replayable;
  final Color accent;
  final ValueChanged<String> onReplay;
  final VoidCallback onRestart;

  const _RunEndPanel({
    required this.progress,
    required this.endingTitle,
    required this.received,
    required this.totalPhotos,
    required this.replayable,
    required this.accent,
    required this.onReplay,
    required this.onRestart,
  });

  /// 안 본 갈래가 남은 대화 고르기
  void _pickReplay(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surfaceWhite,
      constraints: const BoxConstraints(maxWidth: 560),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            children: [
              const Text('안 본 갈래 다시 보기', style: AppTextStyles.appBarTitle),
              const SizedBox(height: 4),
              const Text('고른 대화를 처음부터 다시 봐요. 안 고른 선택지는 ✨로 보이고, 끝나면 진행은 그대로예요.',
                  style: AppTextStyles.systemNotice),
              const SizedBox(height: 10),
              for (final r in replayable)
                ListTile(
                  key: ValueKey('replay_${r.event.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.auto_awesome_rounded, color: accent),
                  title: Text(r.event.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('안 고른 선택지 ${r.unseenChoices}개',
                      style: AppTextStyles.messageTime),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onReplay(r.event.id);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cleared = progress == StoryProgress.cleared;
    final message = switch (progress) {
      StoryProgress.cleared =>
        '${endingTitle == null || endingTitle!.isEmpty ? '공략 완료' : '공략 완료 · $endingTitle'}'
            '${totalPhotos > 0 ? '\n받은 사진 $received / $totalPhotos장' : ''}',
      StoryProgress.stuck => '다른 선택을 해 보면 이야기가 이어질지도 몰라요',
      StoryProgress.playing => '',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.systemNotice,
          ),
          const SizedBox(height: 8),
          if (cleared && replayable.isNotEmpty) ...[
            OutlinedButton.icon(
              key: const ValueKey('replay_button'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: accent, side: BorderSide(color: accent)),
              onPressed: () => _pickReplay(context),
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: Text(received < totalPhotos
                  ? '못 받은 사진 모으기 (안 본 갈래 다시 보기)'
                  : '안 본 갈래 다시 보기'),
            ),
            const SizedBox(height: 6),
          ],
          ElevatedButton.icon(
            onPressed: onRestart,
            icon: const Icon(Icons.replay_rounded, size: 18),
            label: Text(cleared ? '처음부터 다시 하기 (안 본 선택지는 ✨)' : '처음부터 다시 하기'),
          ),
        ],
      ),
    );
  }
}

/// 자유대화 방에 아직 톡이 없을 때 가운데 안내
class _FreeRoomIntro extends StatelessWidget {
  const _FreeRoomIntro({required this.name, required this.accent});

  final String name;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey('free_room_intro'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 40, color: accent),
            const SizedBox(height: 12),
            const Text('자유대화 방', style: AppTextStyles.appBarTitle),
            const SizedBox(height: 6),
            Text(
              '정해진 이야기 없이 $name의 설정과 내 설정대로 AI가 답해요.\n'
              '호감도는 오르지 않고, 스토리 방과 따로 이어져요. 먼저 말을 걸어 보세요.',
              textAlign: TextAlign.center,
              style: AppTextStyles.systemNotice,
            ),
          ],
        ),
      ),
    );
  }
}

/// 서비스 말랑이 이름 옆 작은 표시
class _ServiceBadge extends StatelessWidget {
  const _ServiceBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
          color: const Color(0xFFFCEFD2),
          borderRadius: BorderRadius.circular(999)),
      child: const Text('서비스',
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6B4800))),
    );
  }
}
