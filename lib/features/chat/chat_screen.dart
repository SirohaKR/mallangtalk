import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/models/mallangtalk_models.dart';
import '../../shared/widgets/character_avatar.dart';
import '../library/character_library.dart';
import '../settings/byok_settings.dart';
import '../settings/user_profile.dart';
import 'start_chat.dart';
import 'chat_notifier.dart';

/// [초보자 노트] 리얼 메신저 스타일 채팅 화면입니다.
/// - 호감도 점수나 (+호감도), (실시간 AI 응답), 괄호 지문()을 모두 제거해 실제 카톡처럼 몰입감을 높였습니다.
/// - 유저나 캐릭터가 찍은 사진이 대화방 말풍선 안에 직접 올라오며, 클릭하면 크게 볼 수 있습니다.
/// - 내가 단문으로 여러 번 연속해서 보내는 동안에는 캐릭터가 답장하지 않고 기다려 줍니다.
/// - 상단 버튼으로 앨범(모은 컷씬)과 설정(내 AI 키)으로 이동합니다.
/// 지운 캐릭터의 주소로 들어오면 안내만 보여주고, 있으면 대화방을 엶
class ChatRoomPage extends ConsumerWidget {
  const ChatRoomPage({super.key, required this.characterId});

  final String characterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exists = ref.watch(characterBundleProvider(characterId).select((b) => b != null));
    if (!exists) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('이 캐릭터는 내 캐릭터 목록에 없어요', style: AppTextStyles.systemNotice)),
      );
    }
    return ChatScreen(characterId: characterId);
  }
}

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.characterId});

  final String characterId;

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
      ref.read(chatRoomsProvider.notifier).open(widget.characterId);
      final notifier = ref.read(chatRoomProvider(widget.characterId).notifier);
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

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
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

  @override
  Widget build(BuildContext context) {
    final id = widget.characterId;
    final chatState = ref.watch(chatRoomProvider(id));
    final notifier = ref.read(chatRoomProvider(id).notifier);
    final hasApiKey = ref.watch(byokSettingsProvider.select((s) => s.hasKey));

    ref.listen<ChatRoomState>(chatRoomProvider(id), (prev, next) {
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
      backgroundColor: AppColors.chatRoomBackground,
      appBar: AppBar(
        leading: IconButton(
          tooltip: '채팅방 목록',
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.canPop() ? context.pop() : context.go('/chats'),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            CharacterAvatar(character: chatState.character, radius: 18),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(chatState.character.name, overflow: TextOverflow.ellipsis),
                  Text(
                    chatState.character.statusMessage,
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
                  askChatNickname(context, ref, chatState.character);
                case 'tempo':
                  pickChatTempo(context, ref, chatState.character);
                case 'restart':
                  notifier.restart();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'nickname',
                child: Text('내 별명: ${ref.read(chatNicknameProvider(id))}'),
              ),
              const PopupMenuItem(value: 'tempo', child: Text('대화 속도')),
              const PopupMenuItem(value: 'restart', child: Text('처음부터 다시')),
            ],
          ),
          // [AI 자유대화 ON/OFF] 토글: 켜면 선택지 아래에 직접 입력창이 열림
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '자유대화',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: chatState.isByokAiModeEnabled
                        ? AppColors.aiActivePurple
                        : AppColors.textSecondary,
                  ),
                ),
                Switch(
                  value: chatState.isByokAiModeEnabled,
                  activeTrackColor: AppColors.aiActivePurple,
                  onChanged: notifier.toggleDirectInputMode,
                ),
              ],
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // 1. 대화창 메시지 리스트
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: AppSpacing.screenPadding,
                  itemCount: chatState.messages.length +
                      (chatState.isCharacterTyping ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == chatState.messages.length &&
                        chatState.isCharacterTyping) {
                      return const _TypingIndicatorBubble();
                    }
                    final msg = chatState.messages[index];
                    if (msg.isSystem) {
                      return _SystemNoticeRow(text: msg.text);
                    }
                    return _MessageBubbleRow(
                      message: msg,
                      onPhotoTap: msg.hasPhoto
                          ? () => notifier.openPhotoPreview(msg.photoLabel!)
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
                    if (chatState.progress != StoryProgress.playing)
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
                            onPressed: () => notifier.selectChoice(choice),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
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

                    if (chatState.isByokAiModeEnabled) ...[
                      if (!hasApiKey)
                        GestureDetector(
                          onTap: () => context.go('/settings'),
                          child: const Padding(
                            padding: EdgeInsets.only(bottom: 6),
                            child: Text(
                              '설정에서 내 Claude API 키를 넣으면 진짜 AI가 답해요 →',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.systemNotice,
                            ),
                          ),
                        ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          // 대화방에 내가 직접 사진을 찍어 올리는 카메라 버튼!
                          IconButton(
                            tooltip: '사진 찍어 올리기',
                            onPressed: () => _showUserPhotoSenderSheet(notifier),
                            icon: const Icon(
                              Icons.camera_alt_outlined,
                              color: AppColors.primaryNavy,
                            ),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _inputController,
                              focusNode: _inputFocus,
                              autofocus: true,
                              onChanged: notifier.onUserTypingChanged,
                              textInputAction: TextInputAction.send,
                              decoration: const InputDecoration(
                                hintText: '짧게 여러 번 끊어서 연속으로 보내보세요...',
                              ),
                              // 엔터를 눌러도 키보드·커서가 내려가지 않게 (웹에서 연속 입력)
                              onEditingComplete: () {},
                              onSubmitted: (_) => _send(notifier),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed: () => _send(notifier),
                            icon: const Icon(Icons.send_rounded),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          // 3. 대화방에 올라온 사진을 눌렀을 때 크게 보는 뷰어
          if (chatState.previewPhotoLabel != null)
            _PhotoViewerModal(
              photoLabel: chatState.previewPhotoLabel!,
              onClose: notifier.closePhotoPreview,
            ),

        ],
      ),
    );
  }
}

/// 말풍선(텍스트 + 대화방 사진 카드 + 읽음 '1') 위젯
class _MessageBubbleRow extends StatelessWidget {
  final ChatMessageLog message;
  final VoidCallback? onPhotoTap;

  const _MessageBubbleRow({
    required this.message,
    this.onPhotoTap,
  });

  @override
  Widget build(BuildContext context) {
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
                color: isUser ? AppColors.myBubble : AppColors.partnerBubble,
                borderRadius: BorderRadius.circular(AppSpacing.bubbleRadius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 사진이 포함된 말풍선이면 대화방 안에 사진 카드 표시!
                  if (message.hasPhoto) ...[
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
                            const Icon(
                              Icons.photo_camera_back_rounded,
                              size: 36,
                              color: AppColors.primaryPink,
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
                  Text(message.text, style: AppTextStyles.chatBubbleBody),
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
                  offset: Offset(0, -3 * _bounce((_controller.value - i * 0.18) % 1.0)),
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: AppColors.textMuted.withValues(
                        alpha: 0.45 + 0.55 * _bounce((_controller.value - i * 0.18) % 1.0),
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

/// 대화방에 올라온 사진을 탭했을 때 전체 화면으로 보여주는 모달
class _PhotoViewerModal extends StatelessWidget {
  final String photoLabel;
  final VoidCallback onClose;

  const _PhotoViewerModal({
    required this.photoLabel,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black87,
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surfaceWhite,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 240,
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.chatRoomBackground,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.image_rounded,
                      size: 52,
                      color: AppColors.primaryPink,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      photoLabel,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.chatBubbleBody,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onClose,
                  child: const Text('닫기'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
