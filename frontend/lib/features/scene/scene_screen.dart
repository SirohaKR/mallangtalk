import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/claude_chat_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/character_avatar.dart';
import '../chat/chat_ai_sheet.dart';
import '../chat/chat_notifier.dart';
import '../chat/chat_theme.dart';
import '../chat/memory_sheet.dart';
import '../library/character_library.dart';
import '../settings/byok_settings.dart';
import '../settings/user_profile.dart';
import 'scene_room.dart';

/// 지문(괄호) 글씨색: 대표색을 살짝 섞은 차분한 회보라
Color sceneNarrationColor(Color accent) => Color.lerp(const Color(0xFF7D7488), accent, 0.25)!;

/// 괄호 ( ) 안은 지문 색, 밖은 대사 색으로 나눠 그림
TextSpan sceneTextSpan(String text, {required Color narration, required Color dialogue}) {
  final spans = <InlineSpan>[];
  final re = RegExp(r'[(（][^)）]*[)）]?');
  var at = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start), style: TextStyle(color: dialogue, fontWeight: FontWeight.w600)));
    spans.add(TextSpan(text: m.group(0), style: TextStyle(color: narration)));
    at = m.end;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at), style: TextStyle(color: dialogue, fontWeight: FontWeight.w600)));
  return TextSpan(children: spans);
}

/// 주소: /scene/캐릭터ID (스토리 톡 방에서), /scene/캐릭터ID?free=1 (자유대화 톡 방에서)
class SceneRoomPage extends ConsumerWidget {
  const SceneRoomPage({super.key, required this.characterId, this.free = false});
  final String characterId;
  final bool free;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exists = ref.watch(characterBundleProvider(characterId).select((b) => b != null));
    if (!exists) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('이 캐릭터는 내 캐릭터 목록에 없어요', style: AppTextStyles.systemNotice)),
      );
    }
    return SceneScreen(sourceRoomId: free ? freeRoomId(characterId) : characterId);
  }
}

class SceneScreen extends ConsumerStatefulWidget {
  const SceneScreen({super.key, required this.sourceRoomId});
  final String sourceRoomId;

  @override
  ConsumerState<SceneScreen> createState() => _SceneScreenState();
}

class _SceneScreenState extends ConsumerState<SceneScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  static const _paper = Color(0xFFFBF8F4);

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });

  void _send(SceneRoomNotifier notifier) {
    if (notifier.send(_input.text)) _input.clear();
  }

  Future<bool> _ask(String title, String body, String ok, {Key? bodyKey}) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(body, key: bodyKey),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
          ],
        ),
      ) ==
      true;

  /// 쓰레기통: 내 입력과 그 뒤 장면을 지움
  Future<void> _deleteTurn(String id, SceneRoomNotifier notifier) async {
    if (await _ask('이 부분을 지울까요?', '내가 쓴 입력과 그 뒤에 이어진 장면이 함께 지워져요. 로어북에 들어간 요약은 남아요.', '지우기')) {
      notifier.deleteTurn(id);
    }
  }

  /// 재전송: 예상 비용을 보여 주고, 확인하면 같은 입력으로 장면을 다시 받음
  Future<void> _resend(String id, SceneRoomNotifier notifier) async {
    final est = notifier.estimateResend(id);
    final ai = ref.read(roomByokProvider(sceneAiRoom(widget.sourceRoomId)));
    String won(double w) => w < 10 ? '10원 안쪽' : '${(w / 10).round() * 10}원';
    final cost = est.won == null
        ? '이 모델은 가격을 몰라 금액은 어림 못 해요'
        : '약 ${won(est.won!)} (짧게 와서 이어 쓰면 최대 ${won(est.maxWon!)})';
    final ok = await _ask(
      '장면을 다시 받을까요?',
      '지금 장면은 지우고, 내 입력 그대로 ${aiModelName(ai)}에게 다시 써 달라고 해요.\n\n'
          '예상 사용량: $cost\n입력 약 ${(est.inputTokens / 1000).toStringAsFixed(1)}천 + 출력 약 ${est.outputTokens ~/ 1000}천 토큰',
      '다시 받기',
      bodyKey: const ValueKey('scene_resend_cost'),
    );
    if (ok) await notifier.resend(id);
  }

  Future<void> _menu(String value, SceneRoomNotifier notifier, String name) async {
    switch (value) {
      case 'lorebook':
        showMemorySheet(context,
            characterName: name,
            memories: notifier.sharedMemories,
            onChanged: ref.read(chatRoomProvider(widget.sourceRoomId).notifier).setMemories);
      case 'ai':
        showChatAiSheet(context, accent: ChatTheme.of(ref.read(chatRoomProvider(widget.sourceRoomId)).character).accent,
            roomId: sceneAiRoom(widget.sourceRoomId), onlyHereFirst: true);
      case 'end':
        await notifier.endScene();
      case 'clear':
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('현실 장면 방을 비울까요?'),
            content: const Text('장면 기록이 지워져요. 로어북에 들어간 요약은 톡 방에 그대로 남아요.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
              TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('비우기')),
            ],
          ),
        );
        if (ok == true) notifier.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.sourceRoomId;
    final scene = ref.watch(sceneRoomProvider(source));
    final notifier = ref.read(sceneRoomProvider(source).notifier);
    final character = ref.watch(chatRoomProvider(source).select((s) => s.character));
    final memoryCount = ref.watch(chatRoomProvider(source).select((s) => s.memories.length));
    final nickname = ref.watch(chatNicknameProvider(characterIdOfRoom(source)));
    final theme = ChatTheme.of(character);
    final narration = sceneNarrationColor(theme.accent);
    ref.listen(sceneRoomProvider(source), (prev, next) {
      if (prev?.lines.length != next.lines.length || prev?.writing != next.writing) _toBottom();
    });

    final lines = scene.lines.reversed.toList();
    final est = notifier.estimate(_input.text);
    String won(double w) => w < 10 ? '10원 안쪽' : '${(w / 10).round() * 10}원';
    final cost = est.won == null
        ? '이 모델은 가격을 몰라 비용을 어림 못 해요'
        : '보내면 약 ${won(est.won!)} (짧게 와서 이어 쓰면 최대 ${won(est.maxWon!)})';
    final ai = ref.watch(roomByokProvider(sceneAiRoom(source)));

    return Scaffold(
      backgroundColor: _paper,
      appBar: AppBar(
        backgroundColor: _paper,
        titleSpacing: 0,
        title: Row(children: [
          CharacterAvatar(character: character, radius: 17),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(character.name, style: AppTextStyles.appBarTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('현실 장면 · ${isFreeRoom(source) ? '자유대화' : '스토리'} 톡과 로어북 같이 씀',
                  style: AppTextStyles.messageTime, maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
        actions: [
          PopupMenuButton<String>(
            tooltip: '메뉴',
            onSelected: (v) => _menu(v, notifier, character.name),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'lorebook', child: Text('로어북 (대화 요약 $memoryCount개)')),
              const PopupMenuItem(value: 'ai', child: Text('AI 모델 바꾸기')),
              if (scene.sceneOpen && !scene.writing) const PopupMenuItem(value: 'end', child: Text('장면 마치기')),
              if (!scene.isEmpty && !scene.writing) const PopupMenuItem(value: 'clear', child: Text('현실 장면 방 비우기')),
            ],
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: scene.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('톡 방에서 말풍선을 꾹 누르고\n\'현실 장면으로\'를 고르면\n그 톡 바로 뒤의 장면이 여기서 시작돼요',
                        textAlign: TextAlign.center, style: AppTextStyles.systemNotice),
                  ),
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: ListView.builder(
                      controller: _scroll,
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      itemCount: lines.length + 1,
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return _Status(
                            scene: scene,
                            name: character.name,
                            accent: theme.accent,
                            onRetry: notifier.retry,
                            onSettings: () => context.push('/settings/ai'),
                          );
                        }
                        final l = lines[i - 1];
                        return switch (l.kind) {
                          'start' => _StartMark(key: ValueKey(l.id), text: l.text, accent: theme.accent),
                          'user' => _UserBlock(
                              key: ValueKey(l.id),
                              id: l.id,
                              text: l.text,
                              name: nickname,
                              accent: theme.accent,
                              narration: narration,
                              canResend: notifier.canResend(l.id),
                              busy: scene.writing,
                              onDelete: () => _deleteTurn(l.id, notifier),
                              onResend: () => _resend(l.id, notifier)),
                          'story' => Padding(
                              key: ValueKey(l.id),
                              padding: const EdgeInsets.only(bottom: 22),
                              child: SelectableText.rich(
                                sceneTextSpan(l.text, narration: narration, dialogue: AppColors.textPrimary),
                                style: const TextStyle(fontSize: 15.5, height: 1.85, letterSpacing: -0.1),
                              ),
                            ),
                          _ => Padding(
                              key: ValueKey(l.id),
                              padding: const EdgeInsets.only(bottom: 18),
                              child: Center(child: Text(l.text, style: AppTextStyles.systemNotice)),
                            ),
                        };
                      },
                    ),
                  ),
                ),
        ),
        if (scene.sceneOpen)
          Container(
            decoration: const BoxDecoration(
              color: AppColors.surfaceWhite,
              border: Border(top: BorderSide(color: AppColors.borderLight)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: SafeArea(
              top: false,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      '$cost · 입력 약 ${(est.inputTokens / 1000).toStringAsFixed(1)}천 + 출력 약 ${est.outputTokens ~/ 1000}천 토큰',
                      key: const ValueKey('scene_cost'),
                      style: AppTextStyles.messageTime,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 대화 도중 모델 바꾸기 (현실 장면 방만 따로 고를 수 있음)
                  ActionChip(
                    key: const ValueKey('scene_model'),
                    avatar: Icon(Icons.smart_toy_outlined, size: 16, color: theme.accent),
                    label: Text(aiModelName(ai), style: const TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                    onPressed: scene.writing
                        ? null
                        : () => showChatAiSheet(context, accent: theme.accent, roomId: sceneAiRoom(source), onlyHereFirst: true),
                  ),
                ]),
                const SizedBox(height: 6),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('scene_input'),
                      controller: _input,
                      enabled: !scene.writing,
                      minLines: 1,
                      maxLines: 6,
                      maxLength: ClaudeChatClient.sceneInputMaxChars,
                      maxLengthEnforcement: MaxLengthEnforcement.enforced,
                      decoration: const InputDecoration(
                        hintText: '(행동·상황은 괄호 안에) 대사는 그냥 쓰기',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 22),
                    child: IconButton.filled(
                      tooltip: '보내기',
                      style: IconButton.styleFrom(backgroundColor: theme.accent),
                      onPressed: scene.writing || _input.text.trim().isEmpty ? null : () => _send(notifier),
                      icon: const Icon(Icons.send_rounded),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// 맨 아래 상태 줄: 쓰는 중 / 실패 / 키 없음
class _Status extends StatelessWidget {
  const _Status({required this.scene, required this.name, required this.accent, required this.onRetry, required this.onSettings});
  final SceneState scene;
  final String name;
  final Color accent;
  final VoidCallback onRetry;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    if (scene.writing) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: accent)),
          const SizedBox(width: 10),
          Text('$name의 장면을 쓰는 중…', style: AppTextStyles.systemNotice),
        ]),
      );
    }
    final error = scene.error;
    if (error == null) return const SizedBox(height: 4);
    final noKey = error.contains('AI 키');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(children: [
        Text(error, textAlign: TextAlign.center, style: AppTextStyles.systemNotice),
        const SizedBox(height: 6),
        TextButton(
          key: const ValueKey('scene_retry'),
          onPressed: noKey ? onSettings : onRetry,
          child: Text(noKey ? 'AI 연결하러 가기' : '다시 쓰기'),
        ),
      ]),
    );
  }
}

class _StartMark extends StatelessWidget {
  const _StartMark({super.key, required this.text, required this.accent});
  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 22),
        child: Column(children: [
          Row(children: [
            Expanded(child: Divider(color: accent.withValues(alpha: 0.35))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Icon(Icons.auto_stories_outlined, size: 18, color: accent),
            ),
            Expanded(child: Divider(color: accent.withValues(alpha: 0.35))),
          ]),
          const SizedBox(height: 6),
          Text('톡 ‘$text’ 다음, 현실에서', textAlign: TextAlign.center, style: AppTextStyles.messageTime),
        ]),
      );
}

class _UserBlock extends StatelessWidget {
  const _UserBlock({
    super.key,
    required this.id,
    required this.text,
    required this.name,
    required this.accent,
    required this.narration,
    this.canResend = false,
    this.busy = false,
    required this.onDelete,
    required this.onResend,
  });
  final String id;
  final String text;
  final String name;
  final Color accent;
  final Color narration;
  final bool canResend;
  final bool busy;
  final VoidCallback onDelete;
  final VoidCallback onResend;

  Widget _button(String key, String tip, IconData icon, VoidCallback onTap) => Tooltip(
        message: tip,
        child: InkResponse(
          key: ValueKey('${key}_$id'),
          onTap: onTap,
          radius: 16,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(icon, size: 17, color: AppColors.textSecondary),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 22, left: 28),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border(left: BorderSide(color: accent, width: 3)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(name, style: AppTextStyles.speakerName.copyWith(color: accent))),
              // 재전송(이 입력으로 장면 다시 받기, 맨 마지막만)·쓰레기통(입력+그 뒤 장면 지우기)
              if (canResend) _button('scene_resend', '장면 다시 받기', Icons.refresh_rounded, onResend),
              if (!busy) _button('scene_delete', '이 입력과 장면 지우기', Icons.delete_outline_rounded, onDelete),
            ]),
            const SizedBox(height: 4),
            SelectableText.rich(
              sceneTextSpan(text, narration: narration, dialogue: AppColors.textPrimary),
              style: const TextStyle(fontSize: 15, height: 1.75),
            ),
          ]),
        ),
      );
}
