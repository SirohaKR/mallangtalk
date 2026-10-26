import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/models/mallangtalk_models.dart';
import '../../shared/widgets/character_avatar.dart';
import '../../shared/widgets/photo_viewer.dart';
import '../home/friends_screen.dart';
import '../library/character_library.dart';
import '../settings/byok_settings.dart';
import '../settings/user_profile.dart';
import 'start_chat.dart';
import 'chat_ai_sheet.dart';
import 'chat_notifier.dart';
import 'chat_theme.dart';

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
    return ChatScreen(key: ValueKey(free), roomId: free ? freeRoomId(characterId) : characterId);
  }
}

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.roomId});

  /// 스토리 방은 캐릭터 ID, 자유대화 방은 캐릭터 ID#free
  final String roomId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  /// 엔터로 보낸 뒤에도 입력창에 커서를 그대로 둬서 연달아 칠 수 있게 함
  final FocusNode _inputFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // 대화방에 들어오면 채팅방 목록 맨 위로 + 지금까지 온 톡은 읽음
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(chatRoomsProvider.notifier).open(widget.roomId);
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
    notifier.sendUserMessage(text: _inputController.text);
    _inputController.clear();
    notifier.onUserTypingChanged('');
    _inputFocus.requestFocus();
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

  /// 유저가 대화방에서 사진을 찍거나 골라서 올리는 바텀시트
  void _showUserPhotoSenderSheet(ChatRoomNotifier notifier) {
    final presets = [
      '창밖으로 보이는 오늘 하늘 사진',
      '오늘 마시는 아이스 아메리카노 카페 테이블 사진',
      '방금 먹은 점심 메뉴 사진',
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '대화방에 사진 찍어 올리기',
                  style: AppTextStyles.appBarTitle,
                ),
                const SizedBox(height: 6),
                const Text(
                  '보낼 사진을 선택하면 내 말풍선에 사진이 첨부되어 올라갑니다.',
                  style: AppTextStyles.systemNotice,
                ),
                const SizedBox(height: 14),
                for (final label in presets)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.camera_alt_outlined, size: 18),
                      label: Text(label),
                      onPressed: () {
                        Navigator.pop(ctx);
                        notifier.sendUserMessage(
                          text: _inputController.text,
                          photoLabel: label,
                        );
                        _inputController.clear();
                        _scrollToBottom();
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 이 대화방에 올라온 사진들을 크게 보기 (누른 사진부터, 옆으로 밀면 다른 사진)
  Future<void> _openPhotoViewer(ChatMessageLog tapped, ChatRoomState chatState, ScenarioBundle? bundle,
      ChatTheme theme, ChatRoomNotifier notifier) async {
    final photos = chatState.messages.where((m) => m.hasPhoto).toList();
    final start = photos.indexWhere((m) => m.id == tapped.id);
    final albumGroups = {for (final p in bundle?.albumPhotos ?? const <AlbumPhoto>[]) p.label: p.group};
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
            caption: '${photoTimeLabel(m.timestamp)}에 ${m.isUser ? '보냄' : '받음 · ${m.speakerName}'}',
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
    final notifier = ref.read(chatRoomProvider(roomId).notifier);
    final hasApiKey = ref.watch(byokSettingsProvider.select((s) => s.canUseAi));
    final bundle = ref.watch(characterBundleProvider(id));
    final theme = ChatTheme.of(chatState.character);

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

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        // 대표색 윗줄
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: Container(height: 3, color: theme.accent),
        ),
        leading: IconButton(
          tooltip: '채팅방 목록',
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/chats'),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            // 사진을 누르면 캐릭터 프로필
            GestureDetector(
              onTap: () {
                final entry = ref.read(characterLibraryProvider.notifier).byId(id);
                if (entry != null) showCharacterProfile(context, entry, inChat: true);
              },
              child: Tooltip(
                message: '프로필 보기',
                child: CharacterAvatar(character: chatState.character, radius: 18),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(chatState.character.name,
                      overflow: TextOverflow.ellipsis),
                  // 자유대화 방이면 상태 메시지 대신 지금 쓰는 AI (누르면 바꾸기)
                  if (free)
                    GestureDetector(
                      key: const ValueKey('chat_ai_pill'),
                      onTap: () => showChatAiSheet(context, accent: theme.accent),
                      child: Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Color.lerp(AppColors.surfaceWhite, theme.accent, 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '자유대화 · ${aiModelName(ref.watch(byokSettingsProvider))} ▾',
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.messageTime.copyWith(
                            color: Color.lerp(theme.accent, AppColors.textPrimary, 0.35),
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
                case 'switch':
                  // 스토리 방 ↔ 자유대화 방 (지금 방은 닫고 다른 방으로)
                  context.pushReplacement(free ? '/chat/$id' : '/free/$id');
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
              PopupMenuItem(value: 'switch', child: Text(free ? '스토리 대화방으로' : '자유대화 방 열기')),
              const PopupMenuItem(value: 'ai', child: Text('자유대화 AI 고르기')),
              PopupMenuItem(value: 'restart', child: Text(free ? '대화 비우기' : '처음부터 다시')),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // 1. 대화창 메시지 리스트
              Expanded(
                child: free && chatState.messages.isEmpty && !chatState.isCharacterTyping
                    ? _FreeRoomIntro(name: chatState.character.name, accent: theme.accent)
                    : ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: AppSpacing.screenPadding,
                  itemCount: chatState.messages.length +
                      (chatState.isCharacterTyping ? 1 : 0),
                  itemBuilder: (context, reversedIndex) {
                    final typing = chatState.isCharacterTyping ? 1 : 0;
                    if (reversedIndex == 0 && typing == 1) {
                      return const _TypingIndicatorBubble();
                    }
                    final index = chatState.messages.length - 1 - (reversedIndex - typing);
                    final msg = chatState.messages[index];
                    if (msg.isSystem) {
                      return _SystemNoticeRow(text: msg.text);
                    }
                    final image = bundle?.photoFor(msg.photoImage, msg.photoLabel);
                    return _MessageBubbleRow(
                      message: msg,
                      theme: theme,
                      photoUrl: image,
                      onPhotoTap: msg.hasPhoto
                          ? () => _openPhotoViewer(msg, chatState, bundle, theme, notifier)
                          : null,
                    );
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
                    if (!free && chatState.progress != StoryProgress.playing)
                      _RunEndPanel(
                        progress: chatState.progress,
                        collected: chatState.unlockedCutsceneEventIds.length,
                        missed: notifier.missedCutsceneCount,
                        onRestart: notifier.restart,
                      ),
                    if (chatState.currentChoices.isNotEmpty) ...[
                      for (final choice in chatState.currentChoices)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(AppSpacing.choiceRadius),
                                side: BorderSide(color: theme.choiceBorder, width: 1.2),
                              ),
                            ),
                            onPressed: () => notifier.selectChoice(choice),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (choice.userBubbles
                                    .any((b) => b.hasPhoto)) ...[
                                  const Icon(Icons.photo_camera_outlined,
                                      size: 17),
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
                    const SizedBox(height: 4),
                    _InputBar(
                      // 스토리 방이거나 선택지 대사가 쳐지는 중이면 보이기만 하고 못 누름
                      enabled: chatState.isByokAiModeEnabled &&
                          chatState.userDraft.isEmpty,
                      draft: chatState.userDraft,
                      controller: _inputController,
                      focusNode: _inputFocus,
                      onChanged: notifier.onUserTypingChanged,
                      onCamera: () => _showUserPhotoSenderSheet(notifier),
                      onSend: () => _send(notifier),
                      accent: theme.accent,
                    ),
                  ],
                ),
              ),
            ],
          ),

        ],
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
  final ValueChanged<String> onChanged;
  final VoidCallback onCamera;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final typing = draft.isNotEmpty;
    return Row(
      children: [
        IconButton(
          tooltip: '사진 찍어 올리기',
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
                  autofocus: true,
                  onChanged: onChanged,
                  textInputAction: TextInputAction.send,
                  decoration: const InputDecoration(
                    hintText: '짧게 여러 번 끊어서 연속으로 보내보세요...',
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
        IconButton.filled(
          style: IconButton.styleFrom(backgroundColor: accent),
          onPressed: enabled ? onSend : null,
          icon: const Icon(Icons.send_rounded),
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
  final VoidCallback? onPhotoTap;

  const _MessageBubbleRow({
    required this.message,
    required this.theme,
    this.photoUrl,
    this.onPhotoTap,
  });

  @override
  Widget build(BuildContext context) {
    final photo = message.hasPhoto ? CharacterImage.providerFor(photoUrl ?? '') : null;
    final isUser = message.isUser;
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
              constraints: const BoxConstraints(maxWidth: 290),
              padding: AppSpacing.bubblePadding,
              decoration: BoxDecoration(
                color: isUser ? theme.myBubble : AppColors.partnerBubble,
                borderRadius: BorderRadius.circular(AppSpacing.bubbleRadius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                        style: AppTextStyles.chatBubbleBody
                            .copyWith(color: isUser ? theme.myText : null)),
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
  const _TypingIndicatorBubble();

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
  final int collected;
  final int missed;
  final VoidCallback onRestart;

  const _RunEndPanel({
    required this.progress,
    required this.collected,
    required this.missed,
    required this.onRestart,
  });

  @override
  Widget build(BuildContext context) {
    final message = switch (progress) {
      StoryProgress.cleared => '공략 완료! 모은 장면 $collected개',
      StoryProgress.missedCutscenes => '다른 선택을 하면 남은 장면 $missed개를 볼 수 있어요',
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
          ElevatedButton.icon(
            onPressed: onRestart,
            icon: const Icon(Icons.replay_rounded, size: 18),
            label: const Text('처음부터 다시 하기'),
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
